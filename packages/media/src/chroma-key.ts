export type ChromaOptions = {tolerance?: number; edgeStop?: number; dilation?: number; feather?: number; despill?: boolean}
type Background = {achromatic: true; luminance: number} | {achromatic: false; hue: number; luminance: number}

const luminance = (r: number, g: number, b: number) => 0.299 * r + 0.587 * g + 0.114 * b
function hsv(r: number, g: number, b: number): [number, number] {
  const rn = r / 255, gn = g / 255, bn = b / 255
  const max = Math.max(rn, gn, bn), min = Math.min(rn, gn, bn), delta = max - min
  const saturation = max === 0 ? 0 : delta / max
  let hue = 0
  if (delta !== 0) {
    if (max === rn) hue = ((gn - bn) / delta) % 6
    else if (max === gn) hue = (bn - rn) / delta + 2
    else hue = (rn - gn) / delta + 4
    hue = (hue * 60 + 360) % 360
  }
  return [hue, saturation]
}
const hueDistance = (a: number, b: number) => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d }
function median(values: number[]) { values.sort((a, b) => a - b); return values[Math.floor(values.length / 2)] ?? 0 }

export function hasExistingTransparency(data: Uint8ClampedArray, width: number, height: number) {
  if (width < 1 || height < 1) return false

  const total = width * height
  const minimumTransparent = Math.max(16, Math.floor(total * 0.0025))
  const borderTotal = width * 2 + Math.max(0, height - 2) * 2
  const minimumBorder = Math.max(2, Math.floor(borderTotal * 0.02))
  let transparent = 0
  let transparentBorder = 0

  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (data[(y * width + x) * 4 + 3] >= 250) continue
    transparent++
    if (x === 0 || x === width - 1 || y === 0 || y === height - 1) transparentBorder++
  }

  return transparent >= minimumTransparent && transparentBorder >= minimumBorder
}

function sampleBackground(data: Uint8ClampedArray, width: number, height: number): Background {
  const hues: number[] = [], weights: number[] = [], lights: number[] = []
  const patch = Math.max(2, Math.min(16, Math.floor(Math.min(width, height) * 0.04)))
  const sample = (x: number, y: number) => {
    const i = (y * width + x) * 4
    if (data[i + 3] < 250) return
    const [hue, saturation] = hsv(data[i], data[i + 1], data[i + 2])
    lights.push(luminance(data[i], data[i + 1], data[i + 2]))
    if (saturation >= 0.12) { hues.push(hue); weights.push(saturation) }
  }
  for (let y = 0; y < patch; y++) for (let x = 0; x < patch; x++) {
    sample(x, y); sample(width - 1 - x, y); sample(x, height - 1 - y); sample(width - 1 - x, height - 1 - y)
  }
  const light = median(lights)
  if (lights.length === 0) return {achromatic: true, luminance: 255}
  if (hues.length < lights.length * 0.25) return {achromatic: true, luminance: light}
  let sin = 0, cos = 0, total = 0
  hues.forEach((hue, index) => { const weight = weights[index]; sin += Math.sin(hue * Math.PI / 180) * weight; cos += Math.cos(hue * Math.PI / 180) * weight; total += weight })
  return {achromatic: false, hue: (Math.atan2(sin / total, cos / total) * 180 / Math.PI + 360) % 360, luminance: light}
}

export function removeConnectedBackground(data: Uint8ClampedArray, width: number, height: number, options: ChromaOptions = {}) {
  if (width * height > 16_000_000) throw new Error("Decoded image exceeds the 16 megapixel limit")
  const background = sampleBackground(data, width, height)
  const tolerance = options.tolerance ?? 25, edgeStop = options.edgeStop ?? 24
  const mask = new Uint8Array(width * height), queue = new Int32Array(width * height)
  let head = 0, tail = 0
  const matches = (pixel: number) => {
    if (data[pixel + 3] < 10) return true
    if (background.achromatic) return luminance(data[pixel], data[pixel + 1], data[pixel + 2]) >= background.luminance * 0.68
    const [hue, saturation] = hsv(data[pixel], data[pixel + 1], data[pixel + 2])
    return hueDistance(hue, background.hue) <= tolerance && saturation >= 0.08
  }
  const seed = (index: number) => { if (mask[index] === 0) { mask[index] = 2; queue[tail++] = index } }
  for (let x = 0; x < width; x++) { seed(x); seed((height - 1) * width + x) }
  for (let y = 1; y < height - 1; y++) { seed(y * width); seed(y * width + width - 1) }
  while (head < tail) {
    const index = queue[head++], pixel = index * 4
    if (!matches(pixel)) { mask[index] = 3; continue }
    mask[index] = 1
    const x = index % width, y = Math.floor(index / width)
    const sourceLight = luminance(data[pixel], data[pixel + 1], data[pixel + 2])
    for (const next of [x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1, y > 0 ? index - width : -1, y + 1 < height ? index + width : -1]) {
      if (next < 0 || mask[next] !== 0) continue
      const p = next * 4, light = luminance(data[p], data[p + 1], data[p + 2])
      if (Math.abs(sourceLight - light) <= edgeStop && matches(p)) seed(next)
    }
  }
  for (let step = 0; step < (options.dilation ?? 1); step++) {
    const add: number[] = []
    for (let i = 0; i < mask.length; i++) {
      if (mask[i] === 1) continue
      const x = i % width, y = Math.floor(i / width)
      if ((x > 0 && mask[i - 1] === 1) || (x + 1 < width && mask[i + 1] === 1) || (y > 0 && mask[i - width] === 1) || (y + 1 < height && mask[i + width] === 1)) add.push(i)
    }
    add.forEach(i => { mask[i] = 1 })
  }
  for (let i = 0; i < mask.length; i++) {
    const p = i * 4
    if (mask[i] === 1) { data[p] = data[p + 1] = data[p + 2] = data[p + 3] = 0; continue }
    const x = i % width, y = Math.floor(i / width)
    const edge = (x > 0 && mask[i - 1] === 1) || (x + 1 < width && mask[i + 1] === 1) || (y > 0 && mask[i - width] === 1) || (y + 1 < height && mask[i + width] === 1)
    if ((options.feather ?? 1) > 0 && edge) data[p + 3] = Math.min(data[p + 3], 190)
    if (options.despill !== false && !background.achromatic && edge) {
      if (hueDistance(background.hue, 120) < 45) data[p + 1] = Math.min(data[p + 1], (data[p] + data[p + 2]) / 2)
      if (hueDistance(background.hue, 240) < 45) data[p + 2] = Math.min(data[p + 2], (data[p] + data[p + 1]) / 2)
    }
  }
}
