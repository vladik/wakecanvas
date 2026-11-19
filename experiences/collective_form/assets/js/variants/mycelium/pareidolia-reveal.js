import {Container, Graphics, Text} from "pixi.js"

const FIRST_REVEAL_DELAY_MS = 4_000
const BETWEEN_REVEALS_MS = 12_000
const ENTER_DURATION_MS = 6_000
const HOLD_DURATION_MS = 10_000
const EXIT_DURATION_MS = 6_000

export function createPareidoliaReveal({app, roots, nodes, living}) {
  const layer = new Container()
  const contourGlow = new Graphics()
  const contourDrawing = new Graphics()
  const glow = new Graphics()
  const drawing = new Graphics()
  const title = new Text({
    text: "",
    style: {
      fill: 0xf3f1d7,
      fontFamily: "Georgia, serif",
      fontSize: 34,
      fontWeight: "400",
      letterSpacing: 3,
      align: "center",
      dropShadow: {alpha: .6, blur: 12, color: 0x000000, distance: 0},
    },
  })
  title.anchor.set(.5)
  layer.addChild(contourGlow, contourDrawing, glow, drawing, title)
  app.stage.addChild(layer)

  let latestSnapshot = null
  let currentPackage = null
  let active = null
  let nextRevealAt = Date.now() + FIRST_REVEAL_DELAY_MS
  let interpretationIndex = 0
  let lastAnalysisId = null
  let lastDrawAt = 0

  const tick = snapshot => {
    latestSnapshot = snapshot
    const now = Date.now()
    const incomingPackage = validPackage(snapshot?.pareidolia)
    if (incomingPackage) currentPackage = incomingPackage
    const packageData = currentPackage

    if (!packageData) {
      active = null
      restoreBase(roots, nodes, living)
      clearReveal(contourGlow, contourDrawing, glow, drawing, title)
      return
    }

    if (packageData.analysisId !== lastAnalysisId) {
      active = null
      interpretationIndex = 0
      lastAnalysisId = packageData.analysisId
      nextRevealAt = now + FIRST_REVEAL_DELAY_MS
    }

    if (!active && now >= nextRevealAt) {
      const interpretation = packageData.interpretations[interpretationIndex % packageData.interpretations.length]
      const plan = createPlan(packageData, interpretation)

      if (plan) {
        active = {plan, startedAt: now}
        interpretationIndex += 1
        title.text = interpretation.title
      } else {
        nextRevealAt = now + BETWEEN_REVEALS_MS
      }
    }

    if (!active) {
      restoreBase(roots, nodes, living)
      clearReveal(contourGlow, contourDrawing, glow, drawing, title)
      return
    }

    const elapsed = now - active.startedAt
    const total = ENTER_DURATION_MS + HOLD_DURATION_MS + EXIT_DURATION_MS

    if (elapsed >= total) {
      active = null
      nextRevealAt = now + BETWEEN_REVEALS_MS
      restoreBase(roots, nodes, living)
      clearReveal(contourGlow, contourDrawing, glow, drawing, title)
      return
    }

    const phase = revealPhase(elapsed)
    roots.alpha = 1 - phase.strength * .79
    nodes.alpha = 1 - phase.strength * .67
    living.alpha = 1 - phase.strength * .74
    layer.alpha = phase.strength
    title.position.set(app.screen.width / 2, app.screen.height * .88)
    title.alpha = Math.max(0, Math.min(1, (phase.strength - .35) / .4)) * .9

    if (now - lastDrawAt > 32) {
      drawPlan(contourGlow, contourDrawing, glow, drawing, active.plan, app.screen.width, app.screen.height, phase.progress, now)
      lastDrawAt = now
    }
  }

  return {
    tick,
    update(snapshot) {
      latestSnapshot = snapshot
    },
    resize() {
      if (active && latestSnapshot?.pareidolia) {
        active.plan = createPlan(latestSnapshot.pareidolia, active.plan.interpretation) || active.plan
      }
    },
    destroy() {
      restoreBase(roots, nodes, living)
      app.stage.removeChild(layer)
      layer.destroy({children: true})
    },
  }
}

function validPackage(value) {
  return value?.status === "ready" &&
    Array.isArray(value.interpretations) && value.interpretations.length > 0 &&
    Array.isArray(value.network?.contributions) && Array.isArray(value.network?.connections)
    ? value
    : null
}

function createPlan(packageData, interpretation) {
  const selected = new Set(interpretation.connectionIds || [])
  const contributions = new Map(packageData.network.contributions.map(item => [item.id, item]))
  const connections = packageData.network.connections.filter(edge =>
    selected.has(edge.id) && contributions.has(edge.source_id) && contributions.has(edge.target_id)
  )
  if (connections.length === 0) return null
  return {interpretation, contributions, connections, contours: interpretation.contours || []}
}

function revealPhase(elapsed) {
  if (elapsed < ENTER_DURATION_MS) {
    const progress = ease(elapsed / ENTER_DURATION_MS)
    return {strength: progress, progress}
  }
  if (elapsed < ENTER_DURATION_MS + HOLD_DURATION_MS) return {strength: 1, progress: 1}
  const exit = ease((elapsed - ENTER_DURATION_MS - HOLD_DURATION_MS) / EXIT_DURATION_MS)
  return {strength: 1 - exit, progress: 1}
}

function drawPlan(contourGlow, contourDrawing, glow, drawing, plan, width, height, progress, now) {
  contourGlow.clear()
  contourDrawing.clear()
  glow.clear()
  drawing.clear()
  const pulse = .78 + Math.sin(now / 1100) * .16

  drawContours(contourGlow, contourDrawing, plan.contours, width, height, progress, pulse)

  for (const [index, edge] of plan.connections.entries()) {
    const source = plan.contributions.get(edge.source_id)
    const target = plan.contributions.get(edge.target_id)
    const start = {x: source.x * width, y: source.y * height}
    const end = {x: target.x * width, y: target.y * height}
    const localProgress = Math.max(0, Math.min(1, progress * 1.38 - index / Math.max(8, plan.connections.length) * .38))
    const points = organicPoints(start, end, edge.path_seed, 30)
    drawPartial(glow, points, localProgress)
    glow.stroke({color: 0xcff5b6, width: 11, alpha: .055 + pulse * .035})
    drawPartial(drawing, points, localProgress)
    drawing.stroke({color: 0xe9f7d3, width: 2.2 + pulse * .75, alpha: .72 + pulse * .19})

    const tip = points[Math.max(0, Math.min(points.length - 1, Math.floor(localProgress * (points.length - 1))))]
    if (tip && localProgress < .995) {
      drawing.circle(tip.x, tip.y, 2.5 + pulse * 1.2).fill({color: 0xfff9d7, alpha: .86})
    }
  }

  const nodeIds = new Set(plan.connections.flatMap(edge => [edge.source_id, edge.target_id]))
  for (const id of nodeIds) {
    const node = plan.contributions.get(id)
    const x = node.x * width
    const y = node.y * height
    glow.circle(x, y, 17 + pulse * 5).fill({color: 0xcff5b6, alpha: .045})
    drawing.circle(x, y, 3.5 + pulse).fill({color: parseColor(node.color), alpha: .95})
    drawing.circle(x, y, 7 + pulse * 2).stroke({color: 0xf4f2cf, width: .8, alpha: .42})
  }
}

function drawContours(glow, drawing, contours, width, height, progress, pulse) {
  for (const [index, contour] of contours.entries()) {
    if (!Array.isArray(contour.points)) continue
    const points = smoothContour(contour.points, Boolean(contour.closed), width, height)
    const localProgress = Math.max(0, Math.min(1, progress * 1.22 - index * .08))
    if (points.length < 2 || localProgress <= 0) continue

    drawPartial(glow, points, localProgress)
    glow.stroke({color: 0xb9e9a4, width: 18, alpha: .035 + pulse * .022})
    drawPartial(drawing, points, localProgress)
    drawing.stroke({color: 0xd9edc5, width: 1.5 + pulse * .45, alpha: .42 + pulse * .2})

    if (contour.closed && localProgress >= .999) {
      drawing.moveTo(points[0].x, points[0].y)
      for (let pointIndex = 1; pointIndex < points.length; pointIndex++) {
        drawing.lineTo(points[pointIndex].x, points[pointIndex].y)
      }
      drawing.fill({color: 0xb7d5a6, alpha: .035 + pulse * .015})
    }
  }
}

function smoothContour(normalizedPoints, closed, width, height) {
  const source = normalizedPoints
    .filter(point => Array.isArray(point) && point.length === 2)
    .map(([x, y]) => ({x: x * width, y: y * height}))
  if (source.length < (closed ? 3 : 2)) return []

  const segmentCount = closed ? source.length : source.length - 1
  const result = []
  const at = index => closed
    ? source[(index + source.length) % source.length]
    : source[Math.max(0, Math.min(source.length - 1, index))]

  for (let segment = 0; segment < segmentCount; segment++) {
    const p0 = at(segment - 1)
    const p1 = at(segment)
    const p2 = at(segment + 1)
    const p3 = at(segment + 2)
    for (let step = 0; step < 12; step++) {
      const t = step / 12
      const t2 = t * t
      const t3 = t2 * t
      result.push({
        x: .5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
        y: .5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3),
      })
    }
  }
  result.push(closed ? result[0] : source[source.length - 1])
  return result
}

function organicPoints(start, end, seed, segments) {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.max(1, Math.hypot(dx, dy))
  const curve = (random(seed, 1) - .5) * Math.min(52, length * .25)
  const control = {
    x: (start.x + end.x) / 2 - dy / length * curve,
    y: (start.y + end.y) / 2 + dx / length * curve,
  }
  const points = []
  for (let index = 0; index <= segments; index++) {
    const t = index / segments
    const one = 1 - t
    const wave = Math.sin(t * Math.PI * (2 + Math.floor(random(seed, 3) * 2))) * (random(seed, 4) - .5) * 5
    points.push({
      x: one * one * start.x + 2 * one * t * control.x + t * t * end.x - dy / length * wave,
      y: one * one * start.y + 2 * one * t * control.y + t * t * end.y + dx / length * wave,
    })
  }
  return points
}

function drawPartial(graphic, points, progress) {
  if (progress <= 0 || points.length === 0) return
  const count = Math.max(1, Math.min(points.length - 1, Math.ceil(progress * (points.length - 1))))
  graphic.moveTo(points[0].x, points[0].y)
  for (let index = 1; index <= count; index++) graphic.lineTo(points[index].x, points[index].y)
}

function clearReveal(...items) {
  const title = items.pop()
  for (const graphic of items) graphic.clear()
  title.alpha = 0
}

function restoreBase(...layers) {
  for (const layer of layers) layer.alpha = 1
}

function ease(value) {
  const bounded = Math.max(0, Math.min(1, value))
  return bounded * bounded * (3 - 2 * bounded)
}

function random(seed, salt) {
  const value = Math.sin((Number(seed) + Number(salt) * 101.37) * 12.9898) * 43758.5453
  return value - Math.floor(value)
}

function parseColor(value) {
  const parsed = Number.parseInt(String(value || "#d8e7b0").replace("#", ""), 16)
  return Number.isFinite(parsed) ? parsed : 0xd8e7b0
}
