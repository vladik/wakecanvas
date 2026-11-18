import {Container, Graphics, Text} from "pixi.js"
import {
  animateSvgCreatureTarget,
  drawSvgCreatureBody,
  drawSvgCreatureMask as drawTemplateMask,
  drawSvgCreatureOutline,
  hasSvgCreature,
  svgCreatureFeatureRole,
  svgCreatureFeatureTarget,
  svgCreatureLabel,
  svgCreatureNodeTarget as templateNodeTarget,
} from "../../creatures/svg-creatures.js"

const CREATURES = ["fish", "octopus", "jellyfish", "manta", "starfish"]
const FIRST_REVEAL_DELAY_MS = 30_000
const REVEAL_INTERVAL_MS = 35_000
const ENTER_DURATION_MS = 7_000
const HOLD_DURATION_MS = 10_000
const EXIT_DURATION_MS = 8_000
const MINIMUM_NODES = 5

export function createCreatureReveal({app, roots, nodes, living}) {
  const layer = new Container()
  const maskDrawing = new Graphics()
  const drawing = new Graphics()
  const title = new Text({
    text: "",
    style: {
      fill: 0xeaf6dd,
      fontFamily: "Georgia, serif",
      fontSize: 34,
      fontWeight: "400",
      letterSpacing: 5,
      dropShadow: {alpha: .42, blur: 9, color: 0x000000, distance: 0},
    },
  })
  title.anchor.set(.5)
  title.alpha = 0
  layer.addChild(maskDrawing, drawing, title)
  app.stage.addChild(layer)

  let latestSnapshot = null
  let active = null
  let revealCount = 0
  let lastCreature = null
  let nextRevealAt = Date.now() + FIRST_REVEAL_DELAY_MS
  let lastDrawAt = 0

  const tick = snapshot => {
    latestSnapshot = snapshot
    const now = Date.now()

    if (!active && now >= nextRevealAt) {
      const plan = createPlan(snapshot, app.screen.width, app.screen.height, revealCount, lastCreature)

      if (plan) {
        active = {plan, startedAt: now}
        lastCreature = plan.creature
        revealCount += 1
        title.text = creatureLabel(plan.creature)
      } else {
        nextRevealAt = now + 15_000
      }
    }

    if (!active) {
      restoreBase(roots, nodes, living)
      drawing.mask = null
      maskDrawing.clear()
      drawing.clear()
      title.alpha = 0
      return
    }

    const elapsed = now - active.startedAt
    const totalDuration = ENTER_DURATION_MS + HOLD_DURATION_MS + EXIT_DURATION_MS

    if (elapsed >= totalDuration) {
      const completedRevealStartedAt = active.startedAt
      active = null
      nextRevealAt = completedRevealStartedAt + REVEAL_INTERVAL_MS
      restoreBase(roots, nodes, living)
      drawing.mask = null
      maskDrawing.clear()
      drawing.clear()
      title.alpha = 0
      return
    }

    const phase = revealPhase(elapsed)
    const strength = phase.strength
    const usesSvgTemplate = hasSvgCreature(active.plan.creature)
    roots.alpha = 1 - strength * (usesSvgTemplate ? .94 : .73)
    nodes.alpha = 1 - strength * (usesSvgTemplate ? .9 : .66)
    living.alpha = 1 - strength * (usesSvgTemplate ? .88 : .58)
    layer.alpha = strength

    title.position.set(app.screen.width / 2, app.screen.height * .86)
    title.alpha = Math.max(0, Math.min(1, (strength - .42) / .35)) * .82
    title.scale.set(.96 + strength * .04)

    if (now - lastDrawAt >= 33) {
      drawing.mask = usesSvgTemplate ? maskDrawing : null
      drawTemplateMask(maskDrawing, active.plan.creature, app.screen.width, app.screen.height, now)
      drawReveal(drawing, active.plan, app.screen.width, app.screen.height, phase.morph, now)
      lastDrawAt = now
    }
  }

  return {
    tick,
    update(snapshot) {
      latestSnapshot = snapshot
    },
    resize() {
      if (active && latestSnapshot) {
        active.plan = createPlan(
          active.plan.snapshot,
          app.screen.width,
          app.screen.height,
          revealCount,
          active.plan.creature,
          active.plan.creature
        ) || active.plan
      }
    },
    destroy() {
      restoreBase(roots, nodes, living)
      drawing.mask = null
      app.stage.removeChild(layer)
      layer.destroy({children: true})
    },
  }
}

function revealPhase(elapsed) {
  if (elapsed < ENTER_DURATION_MS) {
    const progress = ease(elapsed / ENTER_DURATION_MS)
    return {strength: progress, morph: progress}
  }

  if (elapsed < ENTER_DURATION_MS + HOLD_DURATION_MS) {
    return {strength: 1, morph: 1}
  }

  const exitElapsed = elapsed - ENTER_DURATION_MS - HOLD_DURATION_MS
  const progress = ease(Math.min(1, exitElapsed / EXIT_DURATION_MS))
  return {strength: 1 - progress, morph: 1 - progress}
}

function restoreBase(...layers) {
  for (const layer of layers) layer.alpha = 1
}

function createPlan(snapshot, width, height, revealCount, previousCreature, forcedCreature = null) {
  const contributions = (snapshot?.contributions || []).filter(
    item => item.state === "placed" && Number.isFinite(item.x) && Number.isFinite(item.y)
  )

  if (contributions.length < MINIMUM_NODES) return null

  const byId = new Map(contributions.map(item => [item.id, item]))
  const connections = (snapshot.connections || []).filter(
    edge => byId.has(edge.source_id) && byId.has(edge.target_id)
  )
  const creature = forcedCreature || selectCreature(contributions, revealCount, previousCreature)
  const bounds = contributionBounds(contributions)
  const points = new Map()

  contributions.forEach((item, index) => {
    const source = {x: item.x * width, y: item.y * height}
    const normalized = normalize(item, bounds)
    const role = creatureFeatureRole(creature, index)
    const target = role
      ? creatureFeatureTarget(creature, role, width, height)
      : hasSvgCreature(creature)
        ? templateNodeTarget(creature, index, width, height)
        : creatureTarget(creature, normalized, index, contributions.length, width, height)
    points.set(item.id, {source, target, role, color: parseColor(item.color), size: item.size || 1})
  })

  return {creature, points, connections, snapshot}
}

function selectCreature(contributions, revealCount, previousCreature) {
  if (previousCreature) {
    return CREATURES[(CREATURES.indexOf(previousCreature) + 1) % CREATURES.length]
  }

  return CREATURES[revealCount % CREATURES.length]
}

function contributionBounds(contributions) {
  const xs = contributions.map(item => item.x)
  const ys = contributions.map(item => item.y)
  return {
    minX: Math.min(...xs),
    maxX: Math.max(...xs),
    minY: Math.min(...ys),
    maxY: Math.max(...ys),
  }
}

function normalize(item, bounds) {
  const width = Math.max(.05, bounds.maxX - bounds.minX)
  const height = Math.max(.05, bounds.maxY - bounds.minY)
  return {
    u: (item.x - bounds.minX) / width,
    v: (item.y - bounds.minY) / height,
  }
}

function creatureTarget(creature, point, index, count, width, height) {
  const aspect = Math.min(width, height)
  const center = {x: width * .5, y: height * .49}
  const jitter = deterministic(index * 149 + count * 37)

  switch (creature) {
    case "bird":
      return birdTarget(point, center, aspect, jitter)
    case "butterfly":
      return butterflyTarget(point, center, aspect, jitter)
    case "fish":
      return fishTarget(point, center, aspect, jitter)
    case "jellyfish":
      return jellyfishTarget(point, center, aspect, jitter)
    case "manta":
      return mantaTarget(point, center, aspect, jitter)
    case "starfish":
      return starfishTarget(point, center, aspect, jitter)
    case "pigeon":
      return pigeonTarget(point, center, aspect, jitter)
    case "rabbit":
      return rabbitTarget(point, center, aspect, jitter)
    default:
      return octopusTarget(point, center, aspect, jitter)
  }
}

function birdTarget({u, v}, center, scale, jitter) {
  if (v > .58) {
    return {
      x: center.x - scale * .22 + u * scale * .43,
      y: center.y + (v - .72) * scale * .16 + jitter * 3,
    }
  }

  return {
    x: center.x - scale * (.02 + u * .3),
    y: center.y - scale * (.07 + Math.sin(u * Math.PI) * .24) + (v - .3) * scale * .1 + jitter * 6,
  }
}

function butterflyTarget({u, v}, center, scale, jitter) {
  if (v > .7) {
    return {
      x: center.x - scale * .19 + u * scale * .38,
      y: center.y + (v - .82) * scale * .1 + jitter * 3,
    }
  }

  return {
    x: center.x - scale * (.05 + u * .29),
    y: center.y - Math.sin(u * Math.PI) * scale * (.17 + (1 - v) * .13) + (v - .35) * scale * .08 + jitter * 6,
  }
}

function fishTarget({u, v}, center, scale, jitter) {
  const bodyX = center.x - scale * .27 + u * scale * .52
  const bodyHeight = Math.sin(Math.max(.05, Math.min(.95, u)) * Math.PI) * scale * .16
  return {
    x: bodyX,
    y: center.y + (v - .5) * bodyHeight * 2 + jitter * 6,
  }
}

function octopusTarget({u, v}, center, scale, jitter) {
  if (v < .42) {
    const angle = u * Math.PI
    return {
      x: center.x + Math.cos(angle) * scale * .15,
      y: center.y - scale * .12 - Math.sin(angle) * scale * .16 + v * scale * .08,
    }
  }

  const tentacle = Math.round(u * 5)
  const depth = (v - .42) / .58
  return {
    x: center.x + (tentacle - 2.5) * scale * .075 + Math.sin(depth * Math.PI * 2 + tentacle) * scale * .035,
    y: center.y + scale * (.02 + depth * .34) + jitter * 7,
  }
}

function jellyfishTarget({u, v}, center, scale, jitter) {
  if (v < .38) {
    const horizontal = (u - .5) * 2
    const dome = Math.sqrt(Math.max(0, 1 - horizontal * horizontal))
    return {
      x: center.x + horizontal * scale * .22,
      y: center.y - scale * (.07 + dome * .17) + v * scale * .1 + jitter * 3,
    }
  }

  const tentacle = Math.round(u * 6)
  const depth = (v - .38) / .62
  return {
    x: center.x + (tentacle - 3) * scale * .055 + Math.sin(depth * Math.PI * 2 + tentacle) * scale * .025,
    y: center.y + scale * (.015 + depth * .37) + jitter * 4,
  }
}

function mantaTarget({u, v}, center, scale, jitter) {
  const side = u < .5 ? -1 : 1
  const distance = Math.abs(u - .5) * 2
  if (distance < .18) {
    return {
      x: center.x + (u - .5) * scale * .13,
      y: center.y + (v - .5) * scale * .48,
    }
  }

  const wingHeight = Math.sin(distance * Math.PI) * scale * .16
  return {
    x: center.x + side * scale * (.05 + distance * .39),
    y: center.y + (v - .5) * wingHeight * 2 + jitter * 4,
  }
}

function starfishTarget({u, v}, center, scale, jitter) {
  const armPosition = u * 5
  const arm = Math.floor(armPosition) % 5
  const side = armPosition - Math.floor(armPosition) - .5
  const distance = .07 + v * .34
  const angle = -Math.PI / 2 + arm * Math.PI * 2 / 5 + side * (.52 - v * .3)
  return {
    x: center.x + Math.cos(angle) * scale * distance + jitter * 3,
    y: center.y + Math.sin(angle) * scale * distance + jitter * 3,
  }
}

function pigeonTarget({u, v}, center, scale, jitter) {
  if (v < .42) {
    return {
      x: center.x - scale * .04 + (u - .5) * scale * .48,
      y: center.y - scale * (.07 + Math.sin(u * Math.PI) * .22) + jitter * 4,
    }
  }

  return {
    x: center.x + (u - .5) * scale * .58,
    y: center.y + (v - .62) * scale * .28 + jitter * 3,
  }
}

function rabbitTarget({u, v}, center, scale, jitter) {
  if (v < .28) {
    return {
      x: center.x - scale * (.2 - u * .16),
      y: center.y - scale * (.12 + (1 - v) * .25) + jitter * 3,
    }
  }

  return {
    x: center.x + (u - .5) * scale * .62,
    y: center.y + (v - .58) * scale * .3 + jitter * 3,
  }
}

function creatureFeatureRole(creature, index) {
  if (hasSvgCreature(creature)) return svgCreatureFeatureRole(creature, index)

  const roles = {
    bird: ["eye", "mark-chest"],
    butterfly: ["eye", "mark-wing"],
    fish: ["eye", "mark-gill"],
    octopus: ["eye-left", "eye-right"],
    jellyfish: ["mark-bell-left", "mark-bell-right"],
    manta: ["eye-left", "eye-right"],
    starfish: ["mark-center"],
    pigeon: ["eye", "mark-wing"],
    rabbit: ["eye", "mark-body"],
  }

  return roles[creature]?.[index] || null
}

function creatureFeatureTarget(creature, role, width, height) {
  if (hasSvgCreature(creature)) return svgCreatureFeatureTarget(creature, role, width, height)

  const scale = Math.min(width, height)
  const center = {x: width * .5, y: height * .49}

  const targets = {
    bird: {
      eye: {x: center.x + scale * .185, y: center.y - scale * .048},
      "mark-chest": {x: center.x + scale * .035, y: center.y + scale * .035},
    },
    butterfly: {
      eye: {x: center.x + scale * .175, y: center.y - scale * .025},
      "mark-wing": {x: center.x - scale * .165, y: center.y - scale * .16},
    },
    fish: {
      eye: {x: center.x + scale * .19, y: center.y - scale * .035},
      "mark-gill": {x: center.x + scale * .11, y: center.y + scale * .015},
    },
    octopus: {
      "eye-left": {x: center.x - scale * .055, y: center.y - scale * .11},
      "eye-right": {x: center.x + scale * .055, y: center.y - scale * .11},
    },
    jellyfish: {
      "mark-bell-left": {x: center.x - scale * .075, y: center.y - scale * .12},
      "mark-bell-right": {x: center.x + scale * .075, y: center.y - scale * .12},
    },
    manta: {
      "eye-left": {x: center.x - scale * .075, y: center.y - scale * .095},
      "eye-right": {x: center.x + scale * .075, y: center.y - scale * .095},
    },
    starfish: {
      "mark-center": {x: center.x, y: center.y},
    },
    pigeon: {
      eye: {x: center.x + scale * .23, y: center.y - scale * .16},
      "mark-wing": {x: center.x - scale * .05, y: center.y - scale * .075},
    },
    rabbit: {
      eye: {x: center.x - scale * .225, y: center.y - scale * .06},
      "mark-body": {x: center.x + scale * .06, y: center.y + scale * .015},
    },
  }

  return targets[creature]?.[role] || center
}

function animateCreatureTarget(creature, target, role, width, height, now) {
  if (hasSvgCreature(creature)) {
    return animateSvgCreatureTarget(creature, target, role, width, height, now)
  }

  const scale = Math.min(width, height)
  const centerX = width * .5
  const centerY = height * .49
  const phase = now / 1000
  const point = {...target}

  if (creature === "bird") {
    const wingWeight = point.y < centerY - scale * .045
      ? Math.min(1, Math.abs(point.x - centerX) / (scale * .32) + .25)
      : 0
    point.y += Math.sin(phase * 1.25) * scale * .055 * wingWeight
    point.y += Math.sin(phase * .72) * scale * .006
  } else if (creature === "butterfly") {
    const wingWeight = point.y < centerY - scale * .04 ? 1 : 0
    const opening = .82 + Math.sin(phase * 1.65) * .18
    point.y = centerY + (point.y - centerY) * (wingWeight ? opening : 1)
    point.x += Math.sin(phase * .8) * scale * .006
  } else if (creature === "fish") {
    const tailWeight = Math.max(0, Math.min(1, (centerX - point.x) / (scale * .4)))
    point.y += Math.sin(phase * 1.7 + point.x / scale * 4) * scale * (.009 + tailWeight * .035)
    point.x += Math.sin(phase * .55) * scale * .012
  } else if (creature === "octopus") {
    const depth = Math.max(0, Math.min(1, (point.y - centerY) / (scale * .4)))
    point.x += Math.sin(phase * 1.15 + depth * 5 + point.x / scale * 3) * scale * .035 * depth
    point.y += Math.sin(phase * .65) * scale * .008
  } else if (creature === "jellyfish") {
    const depth = Math.max(0, Math.min(1, (point.y - centerY) / (scale * .4)))
    const pulse = 1 + Math.sin(phase * 1.35) * .055
    point.x = centerX + (point.x - centerX) * pulse
    point.x += Math.sin(phase * 1.1 + depth * 6 + point.x / scale * 4) * scale * .028 * depth
    point.y += Math.sin(phase * .7) * scale * .012
  } else if (creature === "manta") {
    const wingWeight = Math.min(1, Math.abs(point.x - centerX) / (scale * .42))
    point.y += Math.sin(phase * 1.15) * scale * .065 * wingWeight
    point.y += Math.sin(phase * .55) * scale * .008
  } else if (creature === "starfish") {
    const dx = point.x - centerX
    const dy = point.y - centerY
    const pulse = 1 + Math.sin(phase * .8 + Math.atan2(dy, dx) * 2) * .035
    point.x = centerX + dx * pulse
    point.y = centerY + dy * pulse
  } else if (creature === "pigeon") {
    const wingWeight = point.y < centerY - scale * .055 ? 1 : 0
    point.y += Math.sin(phase * 1.35 + point.x / scale * 2) * scale * .04 * wingWeight
    point.y += Math.sin(phase * .7) * scale * .006
  } else if (creature === "rabbit") {
    const earWeight = point.y < centerY - scale * .16 ? 1 : 0
    point.x += Math.sin(phase * .9 + point.y / scale) * scale * .018 * earWeight
    point.y += Math.sin(phase * .72) * scale * .006
  }

  if (role?.startsWith("eye")) point.y += Math.sin(phase * .7) * scale * .003
  return point
}

function drawCreatureMycelium(graphic, creature, width, height, morph, now) {
  if (morph <= .01) return
  const center = {x: width * .5, y: height * .49}
  const scale = Math.min(width, height)

  if (creature === "bird") drawBirdMycelium(graphic, center, scale, morph, now)
  else if (creature === "butterfly") drawButterflyMycelium(graphic, center, scale, morph, now)
  else if (creature === "fish") drawFishMycelium(graphic, center, scale, morph, now)
  else if (creature === "octopus") drawOctopusMycelium(graphic, center, scale, morph, now)
  else if (creature === "jellyfish") drawJellyfishMycelium(graphic, center, scale, morph, now)
  else if (creature === "manta") drawMantaMycelium(graphic, center, scale, morph, now)
  else if (creature === "starfish") drawStarfishMycelium(graphic, center, scale, morph, now)
  else drawSvgCreatureBody(graphic, creature, width, height, morph, now)
}

function drawBirdMycelium(graphic, center, scale, morph, now) {
  const flap = Math.sin(now / 800) * scale * .038

  const bodyStart = center.x - scale * .22
  const bodyEnd = center.x + scale * .2

  for (let index = 1; index < 15; index++) {
    const t = index / 15
    const x = bodyStart + (bodyEnd - bodyStart) * t
    const halfHeight = Math.sin(t * Math.PI) * scale * .085
    graphic.moveTo(x, center.y - halfHeight)
      .quadraticCurveTo(x + Math.sin(index) * 3, center.y, x, center.y + halfHeight)
      .stroke(livingStroke(index, morph, .68))
  }

  const wingRoot = {x: center.x - scale * .015, y: center.y - scale * .025}
  for (let index = 0; index < 17; index++) {
    const t = index / 16
    const tipX = center.x - scale * (.04 + t * .31)
    const tipY = center.y - scale * (.065 + Math.sin(t * Math.PI) * .255) + flap * (.25 + t * .75)
    graphic.moveTo(wingRoot.x, wingRoot.y)
      .quadraticCurveTo(center.x - scale * (.08 + t * .12), center.y - scale * .15 + flap * t, tipX, tipY)
      .stroke(livingStroke(index + 20, morph, .8))
    drawHyphaTip(graphic, tipX, tipY, index, morph, now)
  }

  graphic.moveTo(bodyStart, center.y).lineTo(bodyEnd, center.y)
    .stroke(livingStroke(2, morph, 1.35))

  for (const offset of [-.045, 0, .045]) {
    graphic.moveTo(bodyStart + scale * .025, center.y + offset * scale * .35)
      .lineTo(bodyStart - scale * .12, center.y + offset * scale)
      .stroke(livingStroke(Math.round((offset + .05) * 100), morph, .82))
  }

  graphic.moveTo(bodyEnd - scale * .005, center.y - scale * .035)
    .lineTo(bodyEnd + scale * .095, center.y)
    .lineTo(bodyEnd - scale * .005, center.y + scale * .015)
    .stroke(livingStroke(43, morph, .9))

  drawFlowSignal(graphic, bodyStart, center.y, bodyEnd, center.y, morph, now, 0)
}

function drawButterflyMycelium(graphic, center, scale, morph, now) {
  const opening = .82 + Math.sin(now / 610) * .18
  const root = {x: center.x - scale * .025, y: center.y - scale * .015}

  for (let index = 0; index < 18; index++) {
    const t = index / 17
    const tipX = center.x - scale * (.045 + t * .3)
    const tipY = center.y - (scale * (.05 + Math.sin(t * Math.PI) * .29)) * opening
    graphic.moveTo(root.x, root.y)
      .quadraticCurveTo(center.x - scale * (.08 + t * .13), center.y - scale * .16 * opening, tipX, tipY)
      .stroke(livingStroke(index, morph, .82))
    drawHyphaTip(graphic, tipX, tipY, index, morph, now)
  }

  for (let index = 0; index < 9; index++) {
    const t = index / 8
    const tipX = center.x - scale * (.05 + t * .23)
    const tipY = center.y + scale * (.025 + Math.sin(t * Math.PI) * .16) * (1.08 - opening * .25)
    graphic.moveTo(root.x, root.y)
      .quadraticCurveTo(center.x - scale * (.09 + t * .1), center.y + scale * .09, tipX, tipY)
      .stroke(livingStroke(index + 22, morph, .72))
  }

  const bodyStart = center.x - scale * .19
  const bodyEnd = center.x + scale * .18
  graphic.moveTo(bodyStart, center.y).lineTo(bodyEnd, center.y)
    .stroke(livingStroke(3, morph, 1.45))

  for (let index = 0; index < 7; index++) {
    const x = bodyStart + (bodyEnd - bodyStart) * (index / 7)
    graphic.moveTo(x, center.y - scale * .025).lineTo(x, center.y + scale * .025)
      .stroke(livingStroke(index + 40, morph, .68))
  }

  for (const side of [-1, 1]) {
    graphic.moveTo(bodyEnd - scale * .005, center.y - scale * .015)
      .quadraticCurveTo(bodyEnd + scale * .065, center.y - scale * .07, bodyEnd + scale * .11, center.y - scale * (.07 + side * .035))
      .stroke(livingStroke(side + 51, morph, .7))
  }

  drawFlowSignal(graphic, bodyStart, center.y, bodyEnd, center.y, morph, now, 1)
}

function drawFishMycelium(graphic, center, scale, morph, now) {
  const swim = Math.sin(now / 590)
  const startX = center.x - scale * .29
  const endX = center.x + scale * .29

  graphic.moveTo(startX, center.y + swim * scale * .025)
    .bezierCurveTo(center.x - scale * .08, center.y - scale * .012, center.x + scale * .1, center.y + scale * .012, endX, center.y)
    .stroke(livingStroke(0, morph, 1.45))

  for (let index = 1; index < 19; index++) {
    const t = index / 20
    const x = startX + (endX - startX) * t
    const body = Math.sin(t * Math.PI) * scale * .165
    const wave = Math.sin(now / 590 + t * 3.2) * scale * .012 * (1 - t)
    const controlX = x + Math.sin(index * 2.7) * scale * .012
    graphic.moveTo(x, center.y - body + wave)
      .quadraticCurveTo(controlX, center.y + wave, x, center.y + body + wave)
      .stroke(livingStroke(index, morph, .72))
    drawHyphaTip(graphic, x, center.y - body + wave, index, morph, now)
  }

  for (const side of [-1, 1]) {
    graphic.moveTo(startX, center.y + swim * scale * .025)
      .quadraticCurveTo(startX - scale * .11, center.y + side * scale * .12 + swim * scale * .04, startX - scale * .15, center.y + side * scale * .16)
      .stroke(livingStroke(side + 4, morph, 1.05))
  }

  drawFlowSignal(graphic, startX, center.y, endX, center.y, morph, now, 2)
}

function drawOctopusMycelium(graphic, center, scale, morph, now) {
  for (let index = 0; index < 8; index++) {
    const offset = (index - 3.5) * scale * .043
    const phase = now / (830 + index * 37) + index * .9
    const sway = Math.sin(phase) * scale * .075
    const startX = center.x + offset * .55
    const startY = center.y + scale * .015
    const endX = center.x + offset * 1.75 + sway
    const endY = center.y + scale * (.31 + (index % 3) * .035)
    graphic.moveTo(startX, startY)
      .bezierCurveTo(
        center.x + offset * 1.35 - sway * .45,
        center.y + scale * .12,
        center.x + offset + sway * .72,
        center.y + scale * .23,
        endX,
        endY
      )
      .stroke(livingStroke(index, morph, 1.05))
    drawHyphaTip(graphic, endX, endY, index, morph, now)
  }

  for (let index = 0; index < 9; index++) {
    const t = index / 8
    const y = center.y - scale * .25 + t * scale * .27
    const halfWidth = Math.sin(t * Math.PI * .8) * scale * .165
    graphic.moveTo(center.x - halfWidth, y)
      .quadraticCurveTo(center.x, y + Math.sin(now / 1100 + index) * scale * .006, center.x + halfWidth, y)
      .stroke(livingStroke(index + 8, morph, .7))
  }

  drawFlowSignal(graphic, center.x, center.y - scale * .24, center.x, center.y + scale * .32, morph, now, 3)
}

function drawJellyfishMycelium(graphic, center, scale, morph, now) {
  const pulse = 1 + Math.sin(now / 740) * .055
  const rimY = center.y - scale * .015

  for (let index = 0; index < 15; index++) {
    const t = index / 14
    const horizontal = (t - .5) * 2
    const x = center.x + horizontal * scale * .225 * pulse
    const dome = Math.sqrt(Math.max(0, 1 - horizontal * horizontal))
    const topY = center.y - scale * (.07 + dome * .18)
    graphic.moveTo(center.x, center.y - scale * .24)
      .quadraticCurveTo(x, topY, x, rimY)
      .stroke(livingStroke(index, morph, .76))
    drawHyphaTip(graphic, x, rimY, index + 90, morph, now)
  }

  for (let index = 0; index < 9; index++) {
    const offset = (index - 4) * scale * .047
    const phase = now / (880 + index * 31) + index * .72
    const sway = Math.sin(phase) * scale * .035
    const length = scale * (.27 + deterministic(index * 23) * .13)
    graphic.moveTo(center.x + offset, rimY)
      .bezierCurveTo(
        center.x + offset - sway,
        rimY + length * .34,
        center.x + offset + sway,
        rimY + length * .7,
        center.x + offset + sway * .45,
        rimY + length
      )
      .stroke(livingStroke(index + 20, morph, .92))
  }

  drawFlowSignal(graphic, center.x, center.y - scale * .23, center.x, center.y + scale * .34, morph, now, 6)
}

function drawMantaMycelium(graphic, center, scale, morph, now) {
  const flap = Math.sin(now / 870) * scale * .065

  for (const side of [-1, 1]) {
    for (let index = 0; index < 17; index++) {
      const t = index / 16
      const tipX = center.x + side * scale * (.08 + t * .36)
      const wingShape = Math.sin(t * Math.PI) * scale * .14
      const tipY = center.y + (index % 2 ? wingShape : -wingShape) * .48 + flap * (.2 + t * .8)
      graphic.moveTo(center.x + side * scale * .018, center.y - scale * .08 + t * scale * .16)
        .quadraticCurveTo(center.x + side * scale * (.13 + t * .13), center.y + flap * t, tipX, tipY)
        .stroke(livingStroke(index + (side > 0 ? 30 : 0), morph, .78))
      drawHyphaTip(graphic, tipX, tipY, index + (side > 0 ? 120 : 100), morph, now)
    }
  }

  graphic.moveTo(center.x, center.y - scale * .2)
    .lineTo(center.x, center.y + scale * .32)
    .stroke(livingStroke(4, morph, 1.35))
  graphic.moveTo(center.x, center.y + scale * .22)
    .bezierCurveTo(center.x + scale * .025, center.y + scale * .31, center.x - scale * .025, center.y + scale * .39, center.x, center.y + scale * .45)
    .stroke(livingStroke(8, morph, .9))

  drawFlowSignal(graphic, center.x, center.y - scale * .2, center.x, center.y + scale * .43, morph, now, 7)
}

function drawStarfishMycelium(graphic, center, scale, morph, now) {
  const pulse = Math.sin(now / 1100) * .018

  for (let arm = 0; arm < 5; arm++) {
    const baseAngle = -Math.PI / 2 + arm * Math.PI * 2 / 5
    for (let index = 0; index < 9; index++) {
      const side = (index / 8 - .5) * .45
      const angle = baseAngle + side
      const distance = scale * (.31 + Math.cos(side * Math.PI) * .055 + pulse * scale / scale)
      const tip = {
        x: center.x + Math.cos(angle) * distance,
        y: center.y + Math.sin(angle) * distance,
      }
      const control = {
        x: center.x + Math.cos(baseAngle + side * .35) * distance * .55,
        y: center.y + Math.sin(baseAngle + side * .35) * distance * .55,
      }
      graphic.moveTo(center.x, center.y)
        .quadraticCurveTo(control.x, control.y, tip.x, tip.y)
        .stroke(livingStroke(arm * 11 + index, morph, .74))
      if (index % 2 === 0) drawHyphaTip(graphic, tip.x, tip.y, arm * 20 + index, morph, now)
    }
  }

  graphic.circle(center.x, center.y, scale * .075)
    .stroke({color: 0xdcefc8, width: 1.2, alpha: morph * .35})
  drawFlowSignal(graphic, center.x, center.y, center.x, center.y - scale * .35, morph, now, 8)
}

function drawPigeonMycelium(graphic, center, scale, morph, now) {
  const flap = Math.sin(now / 740) * scale * .04
  const bodyStart = center.x - scale * .28
  const bodyEnd = center.x + scale * .25

  graphic.moveTo(bodyStart, center.y).lineTo(bodyEnd, center.y - scale * .06)
    .stroke(livingStroke(2, morph, 1.4))

  for (let index = 1; index < 15; index++) {
    const t = index / 15
    const x = bodyStart + (bodyEnd - bodyStart) * t
    const halfHeight = Math.sin(t * Math.PI) * scale * .105
    graphic.moveTo(x, center.y - halfHeight - scale * .025)
      .quadraticCurveTo(x + Math.sin(index) * 3, center.y, x, center.y + halfHeight)
      .stroke(livingStroke(index, morph, .7))
  }

  const wingRoot = {x: center.x + scale * .015, y: center.y - scale * .035}
  for (let index = 0; index < 15; index++) {
    const t = index / 14
    const tipX = center.x - scale * (.02 + t * .32)
    const tipY = center.y - scale * (.08 + Math.sin(t * Math.PI) * .24) + flap * (.25 + t * .75)
    graphic.moveTo(wingRoot.x, wingRoot.y)
      .quadraticCurveTo(center.x - scale * (.07 + t * .1), center.y - scale * .15 + flap * t, tipX, tipY)
      .stroke(livingStroke(index + 24, morph, .8))
    drawHyphaTip(graphic, tipX, tipY, index + 70, morph, now)
  }

  drawFlowSignal(graphic, bodyStart, center.y, bodyEnd, center.y - scale * .06, morph, now, 4)
}

function drawRabbitMycelium(graphic, center, scale, morph, now) {
  const breath = Math.sin(now / 1050) * scale * .008
  const bodyStart = center.x - scale * .27
  const bodyEnd = center.x + scale * .29

  graphic.moveTo(bodyStart, center.y).lineTo(bodyEnd, center.y + breath)
    .stroke(livingStroke(3, morph, 1.4))

  for (let index = 1; index < 17; index++) {
    const t = index / 17
    const x = bodyStart + (bodyEnd - bodyStart) * t
    const halfHeight = Math.sin(t * Math.PI) * scale * .12 + breath
    graphic.moveTo(x, center.y - halfHeight)
      .quadraticCurveTo(x + Math.sin(index * 1.7) * 3, center.y, x, center.y + halfHeight)
      .stroke(livingStroke(index, morph, .72))
  }

  const earRoot = {x: center.x - scale * .19, y: center.y - scale * .08}
  for (let index = 0; index < 7; index++) {
    const t = index / 6
    const sway = Math.sin(now / 900 + t) * scale * .014
    graphic.moveTo(earRoot.x + t * scale * .05, earRoot.y)
      .quadraticCurveTo(center.x - scale * (.2 - t * .06) + sway, center.y - scale * .27, center.x - scale * (.11 - t * .035) + sway, center.y - scale * .39)
      .stroke(livingStroke(index + 30, morph, .76))
  }

  for (const x of [center.x - scale * .13, center.x + scale * .18]) {
    graphic.moveTo(x, center.y + scale * .06)
      .quadraticCurveTo(x - scale * .025, center.y + scale * .17, x + scale * .055, center.y + scale * .2)
      .stroke(livingStroke(Math.round(x), morph, .9))
  }

  drawFlowSignal(graphic, bodyStart, center.y, bodyEnd, center.y, morph, now, 5)
}

function livingStroke(index, morph, emphasis = 1) {
  const variation = .72 + deterministic(index * 73 + 11) * .65
  return {
    color: index % 5 === 0 ? 0xe4f5d1 : 0x9dbb8b,
    width: (.65 + variation * .72) * emphasis,
    alpha: morph * (.2 + variation * .16),
  }
}

function drawHyphaTip(graphic, x, y, seed, morph, now) {
  const sway = Math.sin(now / (900 + seed * 17) + seed) * 3
  const length = 5 + deterministic(seed * 41) * 9
  graphic.moveTo(x, y)
    .lineTo(x + sway + (deterministic(seed + 5) - .5) * length, y + (deterministic(seed + 9) - .5) * length)
    .stroke({color: 0xb8d5a4, width: .65, alpha: morph * .26})
  graphic.circle(x + sway * .35, y, .8 + deterministic(seed) * .65)
    .fill({color: 0xe8f7d8, alpha: morph * (.28 + deterministic(seed + 1) * .25)})
}

function drawFlowSignal(graphic, startX, startY, endX, endY, morph, now, seed) {
  const progress = (now / (4200 + seed * 370)) % 1
  const x = startX + (endX - startX) * progress
  const y = startY + (endY - startY) * progress
  graphic.circle(x, y, 2.1).fill({color: 0xf4ffe5, alpha: morph * .72})
  graphic.circle(x, y, 5.5).fill({color: 0xd9f1c5, alpha: morph * .08})
}

function svgCreatureNodeTarget(creature, index, width, height) {
  const template = SVG_CREATURES[creature]
  const mesh = ensureSvgCreatureMesh(template)
  const point = mesh.points[(index * 17 + 9) % mesh.points.length]
  return svgPointToScreen(creature, point, width, height, 0)
}

function drawSvgInteriorMycelium(graphic, creature, width, height, morph, now) {
  const template = SVG_CREATURES[creature]
  if (!template || morph <= .01) return
  const mesh = ensureSvgCreatureMesh(template)
  const screenPoints = mesh.points.map((point, index) => {
    const screen = svgPointToScreen(creature, point, width, height, now)
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
    graphic.circle(point.x, point.y, radius * 3)
      .fill({color: 0xcbe5b5, alpha: morph * .025})
    graphic.circle(point.x, point.y, radius)
      .fill({color: 0xe8f7d8, alpha: morph * (.2 + glow * .25)})
  })
}

function ensureSvgCreatureMesh(template) {
  if (template.mesh) return template.mesh

  const points = []
  const targetCount = 92
  const minimumDistance = Math.min(template.width, template.height) * .045
  let context = null
  let nativePath = null

  if (typeof document !== "undefined" && typeof Path2D !== "undefined") {
    context = document.createElement("canvas").getContext("2d")
    nativePath = new Path2D(template.pathData)
  }

  for (let candidate = 1; candidate < 5000 && points.length < targetCount; candidate++) {
    const point = {
      x: halton(candidate, 2) * template.width,
      y: halton(candidate, 3) * template.height,
    }
    const inside = context && nativePath
      ? context.isPointInPath(nativePath, point.x, point.y)
      : fallbackInsideTemplate(point, template)
    if (!inside) continue
    if (points.some(existing => Math.hypot(existing.x - point.x, existing.y - point.y) < minimumDistance)) continue
    points.push(point)
  }

  if (points.length < 12) {
    points.length = 0
    for (let row = 1; row < 10; row++) {
      for (let column = 1; column < 12; column++) {
        const point = {x: column / 12 * template.width, y: row / 10 * template.height}
        if (fallbackInsideTemplate(point, template)) points.push(point)
      }
    }
  }

  const edges = []
  const edgeKeys = new Set()
  points.forEach((point, source) => {
    const neighbours = points
      .map((candidate, target) => ({target, distance: Math.hypot(candidate.x - point.x, candidate.y - point.y)}))
      .filter(candidate => candidate.target !== source)
      .sort((left, right) => left.distance - right.distance)
      .slice(0, 3)

    neighbours.forEach(({target}) => {
      const key = source < target ? `${source}:${target}` : `${target}:${source}`
      if (edgeKeys.has(key)) return
      edgeKeys.add(key)
      edges.push({source, target})
    })
  })

  template.mesh = {points, edges}
  return template.mesh
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

function fallbackInsideTemplate(point, template) {
  const x = (point.x / template.width - .5) / .48
  const y = (point.y / template.height - .5) / .45
  return x * x + y * y <= 1
}

function svgPointToScreen(creature, point, width, height, now) {
  const transform = svgCreatureTransform(creature, width, height, now)
  return {
    x: point.x * transform.scale + transform.x,
    y: point.y * transform.scale + transform.y,
  }
}

function svgCreature(svg, width, height) {
  const pathData = svg.match(/<path[^>]*\sd="([^"]+)"/i)?.[1]
  if (!pathData) throw new Error("Creature SVG must contain a path")
  return {path: new GraphicsPath(pathData), pathData, width, height, mesh: null}
}

function drawSvgCreatureSilhouette(graphic, creature, width, height, morph, now) {
  const path = transformedSvgCreaturePath(creature, width, height, now)
  if (!path || morph <= .01) return

  graphic.path(path).stroke({color: 0xdff2ca, width: 1.05, alpha: morph * .2})
}

function drawSvgCreatureMask(graphic, creature, width, height, now) {
  graphic.clear()
  const path = transformedSvgCreaturePath(creature, width, height, now)
  if (path) graphic.path(path).fill(0xffffff)
}

function transformedSvgCreaturePath(creature, width, height, now) {
  const template = SVG_CREATURES[creature]
  if (!template) return null
  const transform = svgCreatureTransform(creature, width, height, now)
  const matrix = new Matrix(transform.scale, 0, 0, transform.scale, transform.x, transform.y)

  return template.path.clone(true).transform(matrix)
}

function svgCreatureTransform(creature, width, height, now) {
  const template = SVG_CREATURES[creature]
  if (!template) return {scale: 1, x: 0, y: 0}

  const available = Math.min(width, height) * .74
  const pulse = 1 + Math.sin(now / 1250) * .012
  const scale = available / Math.max(template.width, template.height) * pulse
  const renderedWidth = template.width * scale
  const renderedHeight = template.height * scale
  const centerY = height * .49 + Math.sin(now / 1100) * Math.min(width, height) * .004
  return {
    scale,
    x: width * .5 - renderedWidth * .5,
    y: centerY - renderedHeight * .5,
  }
}

function drawReveal(graphic, plan, width, height, morph, now) {
  graphic.clear()
  const pulse = .96 + Math.sin(now / 1350) * .04
  const interpolated = new Map()

  for (const [id, point] of plan.points) {
    const livingTarget = animateCreatureTarget(plan.creature, point.target, point.role, width, height, now)
    interpolated.set(id, interpolatePoint(point.source, livingTarget, morph, pulse, width, height))
  }

  drawSvgCreatureOutline(graphic, plan.creature, width, height, morph, now)
  drawCreatureMycelium(graphic, plan.creature, width, height, morph, now)

  for (const [index, edge] of plan.connections.entries()) {
    const source = interpolated.get(edge.source_id)
    const target = interpolated.get(edge.target_id)
    if (!source || !target) continue
    const seed = edge.path_seed || edge.id * 977
    const dx = target.x - source.x
    const dy = target.y - source.y
    const length = Math.max(1, Math.hypot(dx, dy))
    const bend = (deterministic(seed) - .5) * Math.min(42, length * .18)
    const control = {
      x: (source.x + target.x) / 2 - dy / length * bend,
      y: (source.y + target.y) / 2 + dx / length * bend,
    }
    const flow = .5 + Math.sin(now / (1800 + index * 37) + seed) * .5
    graphic.moveTo(source.x, source.y).quadraticCurveTo(control.x, control.y, target.x, target.y)
    graphic.stroke({color: index % 4 === 0 ? 0xe8f5d4 : 0x9fba8d, width: .75 + flow * .65, alpha: .2 + morph * .38})

    const signalT = (now / (6000 + (seed % 5000)) + deterministic(seed + 7)) % 1
    const signal = quadraticPoint(source, control, target, signalT)
    graphic.circle(signal.x, signal.y, 1.1 + flow * .9).fill({color: 0xf4ffe5, alpha: .25 + flow * .42})
  }

  drawCreatureOutline(graphic, plan.creature, width, height, morph, now)

  for (const [id, point] of plan.points) {
    const position = interpolated.get(id)
    const glow = .72 + Math.sin(now / (900 + id * 13)) * .28
    const radius = (4.5 + point.size * 3.2) * (.92 + glow * .08)
    graphic.circle(position.x, position.y, radius * 3).fill({color: point.color, alpha: .025 + morph * .035})
    graphic.circle(position.x, position.y, radius).fill({color: point.color, alpha: .45 + glow * .22})
    graphic.circle(position.x, position.y, radius * .45).fill({color: 0xf5ffe8, alpha: .28 + glow * .42})

    if (point.role?.startsWith("eye")) {
      const blink = Math.sin(now / 1450 + id * .7) > .94 ? .18 : 1
      graphic.ellipse(position.x, position.y, radius * 1.35, radius * blink)
        .fill({color: 0xf4ffe8, alpha: morph * .82})
      graphic.circle(position.x + radius * .18, position.y, radius * .42)
        .fill({color: 0x142118, alpha: morph * .9})
    } else if (point.role?.startsWith("mark")) {
      graphic.circle(position.x, position.y, radius * 1.8)
        .stroke({color: 0xeaf8d8, width: 1.1, alpha: morph * .48})
    }
  }
}

function interpolatePoint(source, target, amount, pulse, width, height) {
  const x = source.x + (target.x - source.x) * amount
  const y = source.y + (target.y - source.y) * amount
  return {
    x: width / 2 + (x - width / 2) * (1 + (pulse - 1) * amount),
    y: height / 2 + (y - height / 2) * (1 + (pulse - 1) * amount),
  }
}

function drawCreatureOutline(graphic, creature, width, height, morph, now) {
  const centerX = width / 2
  const centerY = height * .49
  const scale = Math.min(width, height)
  const alpha = (.08 + Math.sin(now / 1600) * .025) * morph
  const style = {color: 0xdff2ca, width: 1.1, alpha}

  if (creature === "bird") {
    const flap = Math.sin(now / 800) * scale * .038
    graphic.moveTo(centerX - scale * .23, centerY)
      .bezierCurveTo(centerX - scale * .1, centerY - scale * .11, centerX + scale * .13, centerY - scale * .1, centerX + scale * .21, centerY - scale * .035)
      .bezierCurveTo(centerX + scale * .18, centerY + scale * .09, centerX - scale * .08, centerY + scale * .11, centerX - scale * .23, centerY)
      .stroke(style)
    graphic.moveTo(centerX - scale * .02, centerY - scale * .025)
      .bezierCurveTo(centerX - scale * .08, centerY - scale * .23 + flap, centerX - scale * .28, centerY - scale * .34 + flap, centerX - scale * .35, centerY - scale * .08 + flap)
      .bezierCurveTo(centerX - scale * .21, centerY - scale * .08 + flap * .4, centerX - scale * .08, centerY - scale * .01, centerX - scale * .02, centerY - scale * .025)
      .stroke(style)
    graphic.moveTo(centerX - scale * .21, centerY - scale * .015)
      .lineTo(centerX - scale * .35, centerY - scale * .075)
      .moveTo(centerX - scale * .21, centerY + scale * .015)
      .lineTo(centerX - scale * .35, centerY + scale * .065)
      .stroke(style)
    graphic.circle(centerX + scale * .17, centerY - scale * .045, scale * .055).stroke(style)
    graphic.moveTo(centerX + scale * .215, centerY - scale * .055)
      .lineTo(centerX + scale * .305, centerY - scale * .025)
      .lineTo(centerX + scale * .215, centerY - scale * .005)
      .stroke(style)
  } else if (creature === "butterfly") {
    const opening = .82 + Math.sin(now / 610) * .18
    graphic.moveTo(centerX - scale * .025, centerY - scale * .015)
      .bezierCurveTo(centerX - scale * .1, centerY - scale * .33 * opening, centerX - scale * .34, centerY - scale * .38 * opening, centerX - scale * .35, centerY - scale * .08 * opening)
      .bezierCurveTo(centerX - scale * .26, centerY - scale * .02, centerX - scale * .1, centerY + scale * .01, centerX - scale * .025, centerY - scale * .015)
      .stroke(style)
    graphic.moveTo(centerX - scale * .025, centerY)
      .bezierCurveTo(centerX - scale * .12, centerY + scale * .05, centerX - scale * .3, centerY + scale * .19, centerX - scale * .29, centerY + scale * .06)
      .bezierCurveTo(centerX - scale * .2, centerY - scale * .01, centerX - scale * .08, centerY - scale * .015, centerX - scale * .025, centerY)
      .stroke(style)
    graphic.ellipse(centerX, centerY, scale * .2, scale * .035).stroke(style)
    graphic.circle(centerX + scale * .18, centerY - scale * .018, scale * .038).stroke(style)
    graphic.moveTo(centerX + scale * .19, centerY - scale * .05)
      .quadraticCurveTo(centerX + scale * .25, centerY - scale * .12, centerX + scale * .3, centerY - scale * .09)
      .moveTo(centerX + scale * .2, centerY - scale * .045)
      .quadraticCurveTo(centerX + scale * .27, centerY - scale * .08, centerX + scale * .31, centerY - scale * .045)
      .stroke(style)
  } else if (creature === "fish") {
    graphic.moveTo(centerX - scale * .26, centerY)
      .bezierCurveTo(centerX - scale * .08, centerY - scale * .22, centerX + scale * .23, centerY - scale * .17, centerX + scale * .29, centerY)
      .bezierCurveTo(centerX + scale * .2, centerY + scale * .18, centerX - scale * .08, centerY + scale * .22, centerX - scale * .26, centerY)
      .moveTo(centerX - scale * .26, centerY)
      .lineTo(centerX - scale * .39, centerY - scale * .15)
      .lineTo(centerX - scale * .39, centerY + scale * .15)
      .lineTo(centerX - scale * .26, centerY)
      .stroke(style)
    graphic.circle(centerX + scale * .19, centerY - scale * .035, 2.4).fill({color: 0xf6ffe8, alpha: alpha * 4})
  } else if (creature === "jellyfish") {
    const pulse = 1 + Math.sin(now / 740) * .055
    graphic.moveTo(centerX - scale * .23 * pulse, centerY - scale * .015)
      .bezierCurveTo(centerX - scale * .21, centerY - scale * .27, centerX + scale * .21, centerY - scale * .27, centerX + scale * .23 * pulse, centerY - scale * .015)
      .quadraticCurveTo(centerX, centerY + scale * .045, centerX - scale * .23 * pulse, centerY - scale * .015)
      .stroke(style)
    for (let index = 0; index < 7; index++) {
      const offset = (index - 3) * scale * .06
      const sway = Math.sin(now / (900 + index * 31) + index) * scale * .035
      graphic.moveTo(centerX + offset, centerY + scale * .005)
        .bezierCurveTo(centerX + offset - sway, centerY + scale * .13, centerX + offset + sway, centerY + scale * .27, centerX + offset + sway * .4, centerY + scale * .38)
        .stroke(style)
    }
  } else if (creature === "manta") {
    const flap = Math.sin(now / 870) * scale * .055
    graphic.moveTo(centerX, centerY - scale * .2)
      .bezierCurveTo(centerX - scale * .14, centerY - scale * .11, centerX - scale * .32, centerY - scale * .05 + flap, centerX - scale * .44, centerY + flap)
      .bezierCurveTo(centerX - scale * .29, centerY + scale * .16 + flap, centerX - scale * .11, centerY + scale * .1, centerX, centerY + scale * .23)
      .bezierCurveTo(centerX + scale * .11, centerY + scale * .1, centerX + scale * .29, centerY + scale * .16 + flap, centerX + scale * .44, centerY + flap)
      .bezierCurveTo(centerX + scale * .32, centerY - scale * .05 + flap, centerX + scale * .14, centerY - scale * .11, centerX, centerY - scale * .2)
      .stroke(style)
    graphic.moveTo(centerX, centerY + scale * .2)
      .bezierCurveTo(centerX + scale * .025, centerY + scale * .3, centerX - scale * .02, centerY + scale * .4, centerX, centerY + scale * .46)
      .stroke(style)
  } else if (creature === "starfish") {
    const points = []
    for (let index = 0; index < 10; index++) {
      const angle = -Math.PI / 2 + index * Math.PI / 5
      const radius = index % 2 === 0 ? scale * .37 : scale * .14
      points.push({x: centerX + Math.cos(angle) * radius, y: centerY + Math.sin(angle) * radius})
    }
    graphic.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach(point => graphic.lineTo(point.x, point.y))
    graphic.lineTo(points[0].x, points[0].y).stroke(style)
  } else if (creature === "octopus") {
    graphic.ellipse(centerX, centerY - scale * .1, scale * .17, scale * .18).stroke(style)
    for (let index = 0; index < 6; index++) {
      const offset = (index - 2.5) * scale * .055
      graphic.moveTo(centerX + offset * .65, centerY + scale * .02)
        .bezierCurveTo(
          centerX + offset * 1.5,
          centerY + scale * .17,
          centerX + offset + Math.sin(index) * scale * .08,
          centerY + scale * .3,
          centerX + offset * 1.35,
          centerY + scale * .38
        )
        .stroke(style)
    }
    graphic.circle(centerX - scale * .055, centerY - scale * .11, 2.5).fill({color: 0xf6ffe8, alpha: alpha * 4})
    graphic.circle(centerX + scale * .055, centerY - scale * .11, 2.5).fill({color: 0xf6ffe8, alpha: alpha * 4})
  }
}

function quadraticPoint(start, control, end, t) {
  const inverse = 1 - t
  return {
    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y,
  }
}

function creatureLabel(creature) {
  return svgCreatureLabel(creature) || {
    bird: "THE BIRD",
    butterfly: "THE BUTTERFLY",
    fish: "THE FISH",
    octopus: "THE OCTOPUS",
    jellyfish: "THE JELLYFISH",
    manta: "THE MANTA RAY",
    starfish: "THE STARFISH",
    pigeon: "THE PIGEON",
    rabbit: "THE RABBIT",
  }[creature]
}

function ease(value) {
  const bounded = Math.max(0, Math.min(1, value))
  return bounded * bounded * (3 - 2 * bounded)
}

function deterministic(seed) {
  const value = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
  return value - Math.floor(value)
}

function parseColor(value) {
  if (typeof value !== "string") return 0xd8e7b0
  const parsed = Number.parseInt(value.replace("#", ""), 16)
  return Number.isFinite(parsed) ? parsed : 0xd8e7b0
}
