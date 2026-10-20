import p5 from "p5"
import {createAudioLevelInput} from "./audio-level-input.js"

const ARTWORK_LIMIT = 16
const MOMENT_LIMIT = 8
const FEATURE_INTERVAL = 7

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
const mix = (from, to, amount) => from + (to - from) * amount

function hash(value) {
  return [...String(value)].reduce((result, character) => ((result * 31) + character.charCodeAt(0)) >>> 0, 2166136261)
}

function contain(image, maximumWidth, maximumHeight) {
  const scale = Math.min(maximumWidth / Math.max(1, image.width), maximumHeight / Math.max(1, image.height))
  return {width: image.width * scale, height: image.height * scale}
}

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("growing-canvas")

  const overlay = document.createElement("div")
  overlay.className = "growing-canvas__overlay"
  overlay.innerHTML = `<div class="growing-canvas__identity"><span>Artwork becomes a shared garden</span><strong></strong></div><div class="growing-canvas__credit"><span>In bloom</span><strong></strong></div><div class="growing-canvas__veil"></div>`
  overlay.querySelector(".growing-canvas__identity strong").textContent = initial.instanceName || "Growing Canvas"
  const creditName = overlay.querySelector(".growing-canvas__credit strong")
  container.appendChild(overlay)

  const audio = createAudioLevelInput(container)
  const artworks = new Map()
  const moments = new Map()
  let destroyed = false
  let generation = 0
  let sceneTime = 0
  let featureTime = FEATURE_INTERVAL
  let featuredId = null
  let sketch = null

  function loadImage(p, item) {
    return new Promise(resolve => p.loadImage(item.url, image => resolve(image), () => resolve(null)))
  }

  async function reconcile(next) {
    if (!sketch || destroyed) return
    const current = ++generation
    const nextArtwork = next.artworks.slice(0, ARTWORK_LIMIT)
    const nextMoments = next.moments.slice(0, MOMENT_LIMIT)
    const artworkIds = new Set(nextArtwork.map(item => String(item.id)))
    const momentIds = new Set(nextMoments.map(item => String(item.id)))

    for (const id of artworks.keys()) if (!artworkIds.has(id)) artworks.delete(id)
    for (const id of moments.keys()) if (!momentIds.has(id)) moments.delete(id)

    const missingArtwork = nextArtwork.filter(item => !artworks.has(String(item.id)))
    const missingMoments = nextMoments.filter(item => !moments.has(String(item.id)))
    const loadedArtwork = await Promise.all(missingArtwork.map(item => loadImage(sketch, item)))
    const loadedMoments = await Promise.all(missingMoments.map(item => loadImage(sketch, item)))
    if (current !== generation || destroyed) return

    nextArtwork.forEach(item => {
      const existing = artworks.get(String(item.id))
      if (existing) existing.item = item
    })
    nextMoments.forEach(item => {
      const existing = moments.get(String(item.id))
      if (existing) existing.item = item
    })
    missingArtwork.forEach((item, index) => {
      if (!loadedArtwork[index]) return
      const seed = hash(item.id)
      artworks.set(String(item.id), {item, image: loadedArtwork[index], seed, growth: 0, heroMix: 0})
      featuredId = String(item.id)
      featureTime = 0
    })
    missingMoments.forEach((item, index) => {
      if (!loadedMoments[index]) return
      moments.set(String(item.id), {item, image: loadedMoments[index], seed: hash(item.id), alpha: 0})
    })

    if (!featuredId || !artworks.has(featuredId)) featuredId = artworks.keys().next().value || null
    updateCredit()
  }

  function updateCredit() {
    const record = artworks.get(featuredId)
    if (!record) {
      creditName.textContent = "Waiting for the first seed"
      return
    }
    creditName.textContent = record.item.showAttribution && record.item.creatorName
      ? `Created by ${record.item.creatorName}`
      : record.item.title || "A new creation"
  }

  function advanceFeature() {
    const ids = [...artworks.keys()]
    if (!ids.length) {
      featuredId = null
      updateCredit()
      return
    }
    const index = Math.max(-1, ids.indexOf(featuredId))
    featuredId = ids[(index + 1) % ids.length]
    updateCredit()
  }

  function drawMoment(p, record, index) {
    record.alpha = mix(record.alpha, 1, 0.018)
    const seed = record.seed
    const width = p.width * (0.22 + (seed % 9) / 100)
    const height = p.height * 0.3
    const column = index % 4
    const row = Math.floor(index / 4) % 2
    const driftX = Math.sin(sceneTime * 0.06 + seed) * p.width * 0.018
    const driftY = Math.cos(sceneTime * 0.045 + seed) * p.height * 0.018
    const x = p.width * ((column + 0.5) / 4) + driftX
    const y = p.height * (row === 0 ? 0.27 : 0.68) + driftY
    const size = contain(record.image, width, height)
    p.push()
    p.translate(x, y)
    p.rotate(Math.sin(sceneTime * 0.035 + index) * 0.025)
    p.tint(255, 30 * record.alpha)
    p.image(record.image, 0, 0, size.width, size.height)
    p.noFill()
    p.stroke(44, 20, 88, 10 * record.alpha)
    p.strokeWeight(1)
    p.rect(-size.width / 2 - 10, -size.height / 2 - 10, size.width + 20, size.height + 20, 18)
    p.pop()
  }

  function plantPosition(p, record, index, count) {
    const rows = count > 8 ? 2 : 1
    const row = index % rows
    const column = Math.floor(index / rows)
    const columns = Math.ceil(count / rows)
    const lane = (column + 0.5) / Math.max(1, columns)
    const jitter = ((record.seed % 1000) / 1000 - 0.5) * Math.min(70, p.width / Math.max(4, columns))
    const height = p.height * (row === 0
      ? 0.52 + ((record.seed >> 7) % 130) / 1000
      : 0.72 + ((record.seed >> 7) % 100) / 1000)
    return {x: p.width * (0.07 + lane * 0.86) + jitter, height}
  }

  function drawPlant(p, record, index, count, sound, featured) {
    const position = plantPosition(p, record, index, count)
    record.growth = mix(record.growth, 1, 0.016)
    record.heroMix = mix(record.heroMix, featured ? 1 : 0, featured ? 0.035 : 0.055)
    const growth = 1 - Math.pow(1 - record.growth, 3)
    const wind = Math.sin(sceneTime * (0.55 + sound * 1.8) + record.seed) * (16 + sound * 85)
    const rootY = p.height + 28
    const tipY = rootY - position.height * growth
    const hue = 92 + (record.seed % 92)

    p.push()
    p.noFill()
    p.stroke(hue, 42, 72, 68)
    p.strokeWeight(clamp(p.width / 420, 2.2, 5.5))
    p.bezier(position.x, rootY, position.x - wind * 0.15, rootY - position.height * 0.35, position.x + wind * 0.72, rootY - position.height * 0.72, position.x + wind, tipY)
    for (let branch = 1; branch <= 3; branch++) {
      const amount = branch / 4
      const branchY = mix(rootY, tipY, amount)
      const direction = branch % 2 ? -1 : 1
      const reach = (30 + (record.seed % 38)) * growth
      p.stroke(hue + branch * 8, 34, 78, 48)
      p.bezier(position.x + wind * amount, branchY, position.x + direction * reach * 0.35, branchY - 15, position.x + direction * reach * 0.72, branchY - 30, position.x + direction * reach, branchY - 42)
      p.noStroke()
      p.fill(hue + branch * 9, 48, 78, 42)
      p.ellipse(position.x + direction * reach, branchY - 42, 28 * growth, 14 * growth)
      p.noFill()
    }

    if (growth > 0.08) {
      const maximum = mix(Math.min(p.width, p.height) * 0.17, Math.min(p.width, p.height) * 0.43, record.heroMix)
      const artX = clamp(mix(position.x + wind, p.width * 0.5, record.heroMix), maximum * 0.58, p.width - maximum * 0.58)
      const artY = clamp(mix(tipY, p.height * 0.43, record.heroMix), maximum * 0.58 + 24, p.height - maximum * 0.58 - 42)
      const size = contain(record.image, maximum, maximum)
      p.noStroke()
      const bloomPulse = 1 + Math.sin(sceneTime * 1.4 + record.seed) * 0.035
      p.fill((hue + 40) % 360, 42, 96, 13 + record.heroMix * 20)
      p.ellipse(artX, artY, Math.max(size.width, size.height) * 1.5 * bloomPulse)
      p.fill((hue + 70) % 360, 35, 98, 6 + record.heroMix * 12)
      p.ellipse(artX, artY, Math.max(size.width, size.height) * 1.78 * bloomPulse)
      p.tint(255, 78 + record.heroMix * 22)
      p.image(record.image, artX, artY, size.width * bloomPulse, size.height * bloomPulse)
    }
    p.pop()
  }

  sketch = new p5(p => {
    p.setup = () => {
      sketch = p
      p.createCanvas(Math.max(1, container.clientWidth), Math.max(1, container.clientHeight))
      p.pixelDensity(Math.min(window.devicePixelRatio || 1, 1.5))
      p.colorMode(p.HSB, 360, 100, 100, 100)
      p.imageMode(p.CENTER)
      p.noiseDetail(3, 0.55)
      p.frameRate(30)
      reconcile(initial)
    }

    p.draw = () => {
      const seconds = Math.min(p.deltaTime / 1000, 0.05)
      const sound = audio.level()
      sceneTime += seconds
      featureTime += seconds
      if (featureTime >= FEATURE_INTERVAL) {
        featureTime = 0
        advanceFeature()
      }

      const context = p.drawingContext
      const gradient = context.createLinearGradient(0, 0, 0, p.height)
      gradient.addColorStop(0, "#0b2130")
      gradient.addColorStop(0.56, "#153f42")
      gradient.addColorStop(1, "#1b241d")
      context.fillStyle = gradient
      context.fillRect(0, 0, p.width, p.height)

      p.blendMode(p.SCREEN)
      ;[...moments.values()].forEach((record, index) => drawMoment(p, record, index))
      p.blendMode(p.BLEND)

      const records = [...artworks.values()]
      records.filter(record => String(record.item.id) !== featuredId)
        .forEach((record, index) => drawPlant(p, record, index, records.length, sound, false))
      const featured = artworks.get(featuredId)
      if (featured) drawPlant(p, featured, records.indexOf(featured), records.length, sound, true)

      p.noStroke()
      for (let index = 0; index < 42; index++) {
        const phase = index * 1.71
        const x = (index * 97 + sceneTime * (8 + sound * 48)) % (p.width + 60) - 30
        const y = p.height - ((index * 61 + sceneTime * (13 + sound * 72)) % (p.height + 80))
        p.fill(46 + index % 35, 44, 96, 12 + sound * 28)
        p.circle(x + Math.sin(sceneTime + phase) * 15, y, 2.5 + sound * 5)
      }
    }

    p.windowResized = () => p.resizeCanvas(Math.max(1, container.clientWidth), Math.max(1, container.clientHeight))
  }, container)

  function onVisibilityChange() {
    if (document.hidden) sketch?.noLoop()
    else sketch?.loop()
  }
  document.addEventListener("visibilitychange", onVisibilityChange)

  return {
    update: reconcile,
    resize() { sketch.resizeCanvas(Math.max(1, container.clientWidth), Math.max(1, container.clientHeight)) },
    destroy() {
      destroyed = true
      generation++
      document.removeEventListener("visibilitychange", onVisibilityChange)
      audio.destroy()
      sketch.remove()
      overlay.remove()
      container.classList.remove("growing-canvas")
      container.replaceChildren()
    },
  }
}
