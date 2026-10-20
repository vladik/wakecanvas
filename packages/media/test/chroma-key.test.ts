import assert from "node:assert/strict"
import test from "node:test"
import {hasExistingTransparency, removeConnectedBackground} from "../src/chroma-key.ts"

type Pixel = [number, number, number, number?]

function fixture(rows: Pixel[][]) {
  const height = rows.length
  const width = rows[0].length
  const data = new Uint8ClampedArray(width * height * 4)

  rows.flat().forEach(([red, green, blue, alpha = 255], index) => {
    data.set([red, green, blue, alpha], index * 4)
  })

  return {data, width, height}
}

function solid(
  width: number,
  height: number,
  background: Pixel,
  object: Pixel,
  objectPixels: Array<[number, number]>
) {
  const rows = Array.from({length: height}, () =>
    Array.from({length: width}, () => [...background] as Pixel)
  )
  objectPixels.forEach(([x, y]) => { rows[y][x] = object })
  return fixture(rows)
}

function alphaMask(data: Uint8ClampedArray) {
  return Array.from({length: data.length / 4}, (_, index) =>
    data[index * 4 + 3] === 0 ? 0 : 1
  )
}

function process(input: ReturnType<typeof fixture>) {
  removeConnectedBackground(input.data, input.width, input.height, {
    tolerance: 28,
    edgeStop: 30,
    dilation: 0,
    feather: 0,
    despill: false,
  })
  return alphaMask(input.data)
}

const center = [[2, 2], [3, 2], [2, 3], [3, 3]] as Array<[number, number]>
const centerGolden = [
  0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0,
  0, 0, 1, 1, 0, 0,
  0, 0, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0,
]

test("golden mask removes connected green screen", () => {
  assert.deepEqual(process(solid(6, 6, [25, 210, 48], [210, 48, 42], center)), centerGolden)
})

test("golden mask removes connected blue screen", () => {
  assert.deepEqual(process(solid(6, 6, [35, 75, 220], [232, 170, 48], center)), centerGolden)
})

test("golden mask removes a white light-box background", () => {
  assert.deepEqual(process(solid(6, 6, [246, 244, 240], [55, 63, 72], center)), centerGolden)
})

test("golden mask tolerates background texture and shadow", () => {
  const rows = Array.from({length: 6}, (_, y) =>
    Array.from({length: 6}, (_, x) =>
      [24 + ((x + y) % 3) * 3, 188 - y * 3, 52 + (x % 2) * 4] as Pixel
    )
  )
  center.forEach(([x, y]) => { rows[y][x] = [185, 55, 44] })
  assert.deepEqual(process(fixture(rows)), centerGolden)
})

test("golden mask preserves an object touching the image edge", () => {
  const objectPixels = [[2, 0], [2, 1], [2, 2], [3, 2]] as Array<[number, number]>
  const result = process(solid(5, 5, [28, 205, 52], [205, 52, 45], objectPixels))
  const expected = Array(25).fill(0)
  objectPixels.forEach(([x, y]) => { expected[y * 5 + x] = 1 })
  assert.deepEqual(result, expected)
})

test("golden mask preserves translucent foreground pixels", () => {
  const input = solid(6, 6, [30, 205, 50], [210, 60, 52, 128], center)
  assert.deepEqual(process(input), centerGolden)
  assert.equal(input.data[(2 * 6 + 2) * 4 + 3], 128)
})

test("rejects decoded images above the allocation limit before examining pixels", () => {
  assert.throws(
    () => removeConnectedBackground(new Uint8ClampedArray(), 4_001, 4_000),
    /16 megapixel limit/
  )
})

test("detects an existing transparent cutout connected to the image border", () => {
  const input = solid(20, 20, [180, 70, 35, 0], [180, 70, 35], [
    [9, 9], [10, 9], [9, 10], [10, 10],
  ])
  assert.equal(hasExistingTransparency(input.data, input.width, input.height), true)
})

test("does not treat a few isolated transparent pixels as a prepared cutout", () => {
  const input = solid(20, 20, [25, 210, 48], [210, 48, 42], center)
  input.data[3] = 0
  assert.equal(hasExistingTransparency(input.data, input.width, input.height), false)
})
