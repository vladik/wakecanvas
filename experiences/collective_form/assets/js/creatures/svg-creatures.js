import {GraphicsPath, Matrix} from "pixi.js"
import pigeonSvg from "../../svg/creatures/pigeon-rig.svg"
import rabbitSvg from "../../svg/creatures/rabbit-rig.svg"

const CREATURES = {
  pigeon: creatureDefinition({
    id: "pigeon",
    label: "THE PIGEON",
    svg: pigeonSvg,
    width: 320,
    height: 220,
    features: [
      {role: "eye", point: {x: 254, y: 76}},
      {role: "mark-wing", point: {x: 169, y: 78}},
    ],
    rig: {
      bodyCenter: {x: 164, y: 124},
      wing: {pivot: {x: 127, y: 125}, bounds: {x1: 105, y1: 24, x2: 226, y2: 141}},
      parts: {
        wing: {pivot: {x: 127, y: 125}, amplitude: .2, speed: 1.35},
        tail: {pivot: {x: 90, y: 126}, amplitude: .045, speed: .72},
        head: {pivot: {x: 218, y: 102}, amplitude: .025, speed: .65},
      },
      motion: "fly",
    },
  }),
  rabbit: creatureDefinition({
    id: "rabbit",
    label: "THE RABBIT",
    svg: rabbitSvg,
    width: 320,
    height: 220,
    features: [
      {role: "eye", point: {x: 78, y: 103}},
      {role: "mark-body", point: {x: 190, y: 132}},
    ],
    rig: {
      bodyCenter: {x: 182, y: 137},
      ears: {pivot: {x: 91, y: 80}, bounds: {x1: 54, y1: 2, x2: 144, y2: 92}},
      parts: {
        "ear-front": {pivot: {x: 87, y: 82}, amplitude: .085, speed: .9},
        "ear-back": {pivot: {x: 108, y: 83}, amplitude: -.065, speed: .78},
        tail: {pivot: {x: 275, y: 124}, amplitude: .08, speed: 1.1},
        head: {pivot: {x: 119, y: 126}, amplitude: .025, speed: .65},
      },
      motion: "breathe",
    },
  }),
}

export function hasSvgCreature(creature) {
  return Boolean(CREATURES[creature])
}

export function svgCreatureLabel(creature) {
  return CREATURES[creature]?.label
}

export function svgCreatureFeatureRole(creature, index) {
  return CREATURES[creature]?.features[index]?.role || null
}

export function svgCreatureFeatureTarget(creature, role, width, height) {
  const definition = CREATURES[creature]
  const feature = definition?.features.find(item => item.role === role)
  if (!definition || !feature) return {x: width / 2, y: height / 2}
  return localToScreen(definition, feature.point, width, height, 0)
}

export function svgCreatureNodeTarget(creature, index, width, height) {
  const definition = CREATURES[creature]
  const mesh = ensureMesh(definition)
  const point = mesh.points[(index * 17 + 9) % mesh.points.length]
  return localToScreen(definition, point, width, height, 0)
}

export function animateSvgCreatureTarget(creature, target, role, width, height, now) {
  const definition = CREATURES[creature]
  if (!definition) return target
  const scale = Math.min(width, height)
  const phase = now / 1000
  const point = {...target}

  if (definition.rig.motion === "fly") {
    const wingWeight = point.y < height * .49 - scale * .055 ? 1 : 0
    point.y += Math.sin(phase * 1.35 + point.x / scale * 2) * scale * .04 * wingWeight
    point.y += Math.sin(phase * .7) * scale * .006
  } else {
    const earWeight = point.y < height * .49 - scale * .16 ? 1 : 0
    point.x += Math.sin(phase * .9 + point.y / scale) * scale * .018 * earWeight
    point.y += Math.sin(phase * .72) * scale * .006
  }

  if (role?.startsWith("eye")) point.y += Math.sin(phase * .7) * scale * .003
  return point
}

export function drawSvgCreatureBody(graphic, creature, width, height, morph, now) {
  const definition = CREATURES[creature]
  if (!definition || morph <= .01) return
  const mesh = ensureMesh(definition)
  const screenPoints = mesh.points.map((point, index) => {
    const rigged = rigLocalPoint(definition, point, now)
    const screen = localToScreen(definition, rigged, width, height, now)
    const drift = 1.4 + deterministic(index * 19) * 2.4
    return {
      x: screen.x + Math.sin(now / (1300 + index * 11) + index) * drift,
      y: screen.y + Math.cos(now / (1450 + index * 13) + index * .7) * drift,
    }
  })

  mesh.edges.forEach((edge, index) => {
    const source = screenPoints[edge.source]
    const target = screenPoints[edge.target]
    const delay = (index % 19) / 19 * .42
    const growth = ease(Math.max(0, Math.min(1, morph * 1.42 - delay)))
    if (growth <= 0) return

    const end = {
      x: source.x + (target.x - source.x) * growth,
      y: source.y + (target.y - source.y) * growth,
    }
    const dx = end.x - source.x
    const dy = end.y - source.y
    const length = Math.max(1, Math.hypot(dx, dy))
    const bend = (deterministic(index * 97 + 5) - .5) * Math.min(13, length * .16)
    const control = {
      x: (source.x + end.x) / 2 - dy / length * bend,
      y: (source.y + end.y) / 2 + dx / length * bend,
    }
    const breath = .78 + Math.sin(now / (1700 + index * 23) + index) * .22

    graphic.moveTo(source.x, source.y)
      .quadraticCurveTo(control.x, control.y, end.x, end.y)
      .stroke({
        color: index % 7 === 0 ? 0xe6f5d3 : 0x9fbd8c,
        width: .65 + breath * .9,
        alpha: morph * (.22 + breath * .22),
      })

    if (growth > .96 && index % 9 === 0) {
      const signalT = (now / (4100 + index * 31) + deterministic(index)) % 1
      const signal = quadraticPoint(source, control, end, signalT)
      graphic.circle(signal.x, signal.y, 1.8).fill({color: 0xf2ffe4, alpha: morph * .7})
    }
  })

  screenPoints.forEach((point, index) => {
    const glow = .55 + Math.sin(now / (1000 + index * 17) + index) * .35
    const radius = .8 + deterministic(index * 31) * 1.25
    graphic.circle(point.x, point.y, radius * 3).fill({color: 0xcbe5b5, alpha: morph * .025})
    graphic.circle(point.x, point.y, radius).fill({color: 0xe8f7d8, alpha: morph * (.2 + glow * .25)})
  })
}

export function drawSvgCreatureOutline(graphic, creature, width, height, morph, now) {
  if (morph <= .01) return
  transformedParts(creature, width, height, now).forEach(({id, path}) => {
    const feature = id === "eye" || id === "nose"
    graphic.path(path).stroke({
      color: feature ? 0xf3ffe8 : 0xdff2ca,
      width: feature ? 1.35 : 1.05,
      alpha: morph * (feature ? .42 : .2),
    })
  })
}

export function drawSvgCreatureMask(graphic, creature, width, height, now) {
  graphic.clear()
  transformedParts(creature, width, height, now).forEach(({path}) => {
    graphic.path(path).fill(0xffffff)
  })
}

function creatureDefinition(options) {
  const parts = [...options.svg.matchAll(/<path[^>]*\sid="([^"]+)"[^>]*\sd="([^"]+)"[^>]*>/gi)]
    .map(match => ({id: match[1], pathData: match[2], path: new GraphicsPath(match[2])}))
  if (parts.length === 0) throw new Error(`Creature SVG ${options.id} must contain named paths`)
  const pathData = parts.map(part => part.pathData).join(" ")
  return {...options, parts, pathData, path: new GraphicsPath(pathData), mesh: null}
}

function ensureMesh(definition) {
  if (definition.mesh) return definition.mesh
  const points = sampleInterior(definition)
  const edges = []
  const edgeKeys = new Set()

  points.forEach((point, source) => {
    points
      .map((candidate, target) => ({target, distance: Math.hypot(candidate.x - point.x, candidate.y - point.y)}))
      .filter(candidate => candidate.target !== source)
      .sort((left, right) => left.distance - right.distance)
      .slice(0, 3)
      .forEach(({target}) => {
        const key = source < target ? `${source}:${target}` : `${target}:${source}`
        if (edgeKeys.has(key)) return
        edgeKeys.add(key)
        edges.push({source, target})
      })
  })

  definition.mesh = {points, edges}
  return definition.mesh
}

function sampleInterior(definition) {
  const points = []
  const targetCount = 92
  const minimumDistance = Math.min(definition.width, definition.height) * .045
  let context = null
  let nativePath = null

  if (typeof document !== "undefined" && typeof Path2D !== "undefined") {
    context = document.createElement("canvas").getContext("2d")
    nativePath = new Path2D(definition.pathData)
  }

  for (let candidate = 1; candidate < 5000 && points.length < targetCount; candidate++) {
    const point = {x: halton(candidate, 2) * definition.width, y: halton(candidate, 3) * definition.height}
    const inside = context && nativePath
      ? context.isPointInPath(nativePath, point.x, point.y)
      : fallbackInside(point, definition)
    if (!inside) continue
    if (points.some(existing => Math.hypot(existing.x - point.x, existing.y - point.y) < minimumDistance)) continue
    points.push(point)
  }

  if (points.length < 12) {
    for (let row = 1; row < 10; row++) {
      for (let column = 1; column < 12; column++) {
        const point = {x: column / 12 * definition.width, y: row / 10 * definition.height}
        if (fallbackInside(point, definition)) points.push(point)
      }
    }
  }

  return points
}

function rigLocalPoint(definition, point, now) {
  const result = {...point}
  const phase = now / 1000
  const body = definition.rig.bodyCenter
  const breathing = 1 + Math.sin(phase * .72) * .018
  result.y = body.y + (result.y - body.y) * breathing

  const region = definition.rig.wing || definition.rig.ears
  if (insideBounds(point, region.bounds)) {
    const direction = definition.rig.wing ? 1 : -1
    const angle = Math.sin(phase * (definition.rig.wing ? 1.35 : .9)) * .075 * direction
    return rotateAround(result, region.pivot, angle)
  }

  return result
}

function insideBounds(point, bounds) {
  return point.x >= bounds.x1 && point.x <= bounds.x2 && point.y >= bounds.y1 && point.y <= bounds.y2
}

function rotateAround(point, pivot, angle) {
  const cosine = Math.cos(angle)
  const sine = Math.sin(angle)
  const x = point.x - pivot.x
  const y = point.y - pivot.y
  return {x: pivot.x + x * cosine - y * sine, y: pivot.y + x * sine + y * cosine}
}

function transformedParts(creature, width, height, now) {
  const definition = CREATURES[creature]
  if (!definition) return []
  const transform = screenTransform(definition, width, height, now)
  const screenMatrix = new Matrix(transform.scale, 0, 0, transform.scale, transform.x, transform.y)

  return definition.parts.map(part => {
    const path = part.path.clone(true)
    const motion = definition.rig.parts?.[part.id]
    if (motion) {
      const angle = Math.sin(now / 1000 * motion.speed) * motion.amplitude
      path.transform(rotationMatrix(motion.pivot, angle))
    }
    path.transform(screenMatrix)
    return {id: part.id, path}
  })
}

function rotationMatrix(pivot, angle) {
  const cosine = Math.cos(angle)
  const sine = Math.sin(angle)
  return new Matrix(
    cosine,
    sine,
    -sine,
    cosine,
    pivot.x - pivot.x * cosine + pivot.y * sine,
    pivot.y - pivot.x * sine - pivot.y * cosine
  )
}

function localToScreen(definition, point, width, height, now) {
  const transform = screenTransform(definition, width, height, now)
  return {x: point.x * transform.scale + transform.x, y: point.y * transform.scale + transform.y}
}

function screenTransform(definition, width, height, now) {
  const available = Math.min(width, height) * .74
  const pulse = 1 + Math.sin(now / 1250) * .012
  const scale = available / Math.max(definition.width, definition.height) * pulse
  const renderedWidth = definition.width * scale
  const renderedHeight = definition.height * scale
  const centerY = height * .49 + Math.sin(now / 1100) * Math.min(width, height) * .004
  return {scale, x: width * .5 - renderedWidth * .5, y: centerY - renderedHeight * .5}
}

function halton(index, base) {
  let fraction = 1
  let result = 0
  let value = index
  while (value > 0) {
    fraction /= base
    result += fraction * (value % base)
    value = Math.floor(value / base)
  }
  return result
}

function fallbackInside(point, definition) {
  const x = (point.x / definition.width - .5) / .48
  const y = (point.y / definition.height - .5) / .45
  return x * x + y * y <= 1
}

function quadraticPoint(start, control, end, t) {
  const inverse = 1 - t
  return {
    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y,
  }
}

function ease(value) {
  const bounded = Math.max(0, Math.min(1, value))
  return bounded * bounded * (3 - 2 * bounded)
}

function deterministic(seed) {
  const value = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
  return value - Math.floor(value)
}
