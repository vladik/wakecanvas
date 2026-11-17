import {Application, Container, Graphics} from "pixi.js"

export async function mount(container, initialSnapshot) {
  const app = new Application()
  await app.init({resizeTo: container, antialias: true, background: "#050806", resolution: Math.min(devicePixelRatio || 1, 2)})
  container.replaceChildren(app.canvas)
  app.canvas.className = "cf-myc-canvas"

  const ambience = new Container()
  const roots = new Container()
  const nodes = new Container()
  const living = new Container()
  app.stage.addChild(ambience, roots, nodes, living)
  const lifeGraphic = new Graphics()
  living.addChild(lifeGraphic)

  let snapshot = initialSnapshot
  let destroyed = false
  let needsRender = true
  let retiringConnections = []
  let retiringNodes = []
  let serverClockOffset = Number(initialSnapshot.serverNow || Date.now()) - Date.now()
  let lastNetworkRender = 0

  const drawAmbience = () => {
    ambience.removeChildren().forEach(child => child.destroy())
    const dust = new Graphics()
    const count = Math.max(45, Math.round(app.screen.width * app.screen.height / 24000))
    for (let index = 0; index < count; index++) {
      const x = random(7717, index * 3) * app.screen.width
      const y = random(7717, index * 3 + 1) * app.screen.height
      const radius = .4 + random(7717, index * 3 + 2) * 1.5
      dust.circle(x, y, radius).fill({color: 0xb8d49a, alpha: .035 + random(index, 9) * .06})
    }
    ambience.addChild(dust)
  }
  drawAmbience()

  const render = () => {
    if (destroyed) return
    const frameNow = performance.now()
    const renderInterval = needsRender ? 45 : 90
    if (frameNow - lastNetworkRender < renderInterval) return
    lastNetworkRender = frameNow
    roots.removeChildren().forEach(child => child.destroy())
    nodes.removeChildren().forEach(child => child.destroy())

    const placed = new Map((snapshot.contributions || []).filter(item => item.state === "placed").map(item => [item.id, item]))
    const detail = visualDetail(placed.size, (snapshot.connections || []).length)
    const now = Date.now()
    let hasActiveGrowth = false

    retiringConnections = retiringConnections.filter(item => item.until > now)
    for (const retiring of retiringConnections) {
      const remaining = Math.max(0, (retiring.until - now) / retiring.duration)
      const withdrawal = remaining > .78 ? 1 : remaining / .78
      const oldGrowth = drawConnection(app, retiring.source, retiring.target, retiring.edge.path_seed, withdrawal, false, 1, 0, 0, 0, detail)
      const lossOfSignal = remaining > .78 ? .78 - (1 - remaining) * 1.2 : .48 + remaining * .26
      oldGrowth.alpha = Math.max(.06, lossOfSignal + Math.sin(now / 110) * .035 * remaining)
      roots.addChild(oldGrowth)
      hasActiveGrowth = true
    }

    retiringNodes = retiringNodes.filter(item => item.until > now)
    for (const retiring of retiringNodes) {
      const remaining = Math.max(0, (retiring.until - now) / retiring.duration)
      const withdrawal = remaining * remaining * (3 - 2 * remaining)
      const oldNode = drawNode(app, retiring.item, detail, withdrawal, withdrawal, true)
      oldNode.alpha = Math.max(0, remaining)
      nodes.addChild(oldNode)
      hasActiveGrowth = true
    }

    for (const [edgeIndex, edge] of (snapshot.connections || []).entries()) {
      const source = placed.get(edge.source_id)
      const target = placed.get(edge.target_id)
      if (!source || !target) continue
      const startedAt = Date.parse(edge.growth_started_at)
      const rawProgress = Math.max(0, Math.min(1, (now + serverClockOffset - startedAt) / edge.growth_duration_ms))
      const progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
      const maturity = Math.max(0, Math.min(1, (now + serverClockOffset - startedAt - edge.growth_duration_ms) / 14000))
      if (progress < 1 || maturity < 1) hasActiveGrowth = true
      const connectionAge = Math.max(0, now + serverClockOffset - startedAt)
      roots.addChild(drawConnection(app, source, target, edge.path_seed, progress, progress < 1, maturity, connectionAge, edge.growth_duration_ms, edgeIndex, detail))
    }

    for (const item of placed.values()) {
      const placedAt = Date.parse(item.updated_at)
      const rawArrival = Number.isFinite(placedAt)
        ? Math.max(0, Math.min(1, (now + serverClockOffset - placedAt) / 7000))
        : 1
      const arrival = rawArrival * rawArrival * (3 - 2 * rawArrival)
      nodes.addChild(drawNode(app, item, detail, arrival, arrival, false))
      if (arrival < 1) hasActiveGrowth = true
    }
    needsRender = hasActiveGrowth
  }

  const renderLiving = () => {
    if (destroyed) return
    lifeGraphic.clear()
    const placed = new Map((snapshot.contributions || []).filter(item => item.state === "placed").map(item => [item.id, item]))
    const now = Date.now()
    drawFrontierLife(lifeGraphic, app, placed, snapshot.connections || [], now, serverClockOffset)
    drawResourceFlow(lifeGraphic, app, placed, snapshot.connections || [], now, serverClockOffset)
  }

  app.ticker.add(() => { render(); renderLiving() })

  return {
    update(next) {
      const nextIds = new Set((next.connections || []).map(edge => edge.id))
      const previousNodes = new Map((snapshot.contributions || []).map(item => [item.id, item]))
      const nextNodes = new Map((next.contributions || []).map(item => [item.id, item]))
      const now = Date.now()
      for (const edge of snapshot.connections || []) {
        if (nextIds.has(edge.id)) continue
        const source = previousNodes.get(edge.source_id)
        const target = previousNodes.get(edge.target_id)
        if (source && target) retiringConnections.push({edge, source, target, duration: 16000, until: now + 16000})
      }
      for (const item of snapshot.contributions || []) {
        if (item.state !== "placed") continue
        const nextItem = nextNodes.get(item.id)
        const removed = !nextItem || nextItem.state !== "placed"
        const moved = nextItem && nextItem.state === "placed" && (nextItem.x !== item.x || nextItem.y !== item.y)
        if (removed || moved) retiringNodes.push({item, duration: 5500, until: now + 5500})
      }
      snapshot = next
      serverClockOffset = Number(next.serverNow || Date.now()) - Date.now()
      needsRender = true
    },
    resize() {
      app.resize()
      drawAmbience()
      needsRender = true
    },
    destroy() {
      destroyed = true
      app.destroy(true, {children: true})
    },
  }
}

function drawConnection(app, source, target, seed, progress, searching, maturity = 1, ageMs = 0, growthDurationMs = 0, densityRank = 0, detail = visualDetail(0, 0)) {
  const graphic = new Graphics()
  const width = app.screen.width
  const height = app.screen.height
  // Route direction is persisted for deterministic identity, but active growth
  // responds from both endpoints so an arriving node can visibly reach several
  // neighbours while the established colony reaches back.
  const start = {x: target.x * width, y: target.y * height}
  const end = {x: source.x * width, y: source.y * height}
  const matureAge = Math.max(0, ageMs - growthDurationMs)
  const routeDistance = Math.hypot(source.x - target.x, source.y - target.y)
  const proximity = Math.max(0, Math.min(1, 1 - routeDistance / .68))
  const proximityDetail = .55 + proximity * .8
  const routeBranches = Math.max(2, Math.round(detail.routeBranches * proximityDetail))
  const matureBranches = Math.max(2, Math.round(detail.matureBranches * proximityDetail))
  const routeDominance = dominanceForRoute(seed, routeDistance, 0.72)
  const routeStrength = (.82 + random(seed, 29) * .3) * remodelingStrength(seed, matureAge, 3100, routeDominance)
  // A route is a small hyphal cord, not several independent connections.
  // Keeping one faint companion strand preserves the organic texture while
  // making multiple routes from a node read as a fan toward distinct targets.
  const companionSide = random(seed, 31) > .5 ? -4.2 : 4.2
  const strands = [
    {offset: companionSide, width: .3, alpha: .11, color: 0x929d8b},
    {offset: 0, width: .68 + (1 - maturity) * .12, alpha: .29, color: 0xd7dfcc},
  ]

  if (searching) drawExplorers(graphic, start, end, seed, progress)

  const settledProgress = searching ? Math.max(0, (progress - .12) / .88) : progress

  for (const [index, strand] of strands.entries()) {
    const path = organicPath(start, end, seed + index * 97, strand.offset)
    const style = {
      color: strand.color,
      width: strand.width * routeStrength,
      alpha: strand.alpha,
      seed: seed + index * 193,
      lifeSeed: seed,
      cord: index === 1,
    }
    if (searching) drawBidirectionalVariablePath(graphic, path, settledProgress, style)
    else drawVariablePath(graphic, path, settledProgress, style)
  }

  drawSideHyphae(graphic, start, end, seed, settledProgress, seed + 97, routeBranches)
  if (settledProgress > .72) drawFusionLoops(graphic, start, end, seed, settledProgress, seed + 97)
  if (settledProgress >= 1) drawAdaptiveMaturation(graphic, start, end, seed, Math.max(0, ageMs - growthDurationMs), densityRank, matureBranches)

  if (progress > 0 && progress < 1) {
    const pulse = 4 + Math.sin(Date.now() / (620 + random(seed, 32) * 480)) * 1.5
    const tipPositions = [settledProgress * .5, 1 - settledProgress * .5]
    for (const tipPosition of tipPositions) {
      const tip = pointOnOrganicPath(start, end, seed + 97, 0, tipPosition)
      graphic.circle(tip.x, tip.y, pulse * 3).fill({color: 0xf3f0dc, alpha: .055})
      graphic.circle(tip.x, tip.y, pulse).fill({color: 0xfffdea, alpha: .92})
    }
  }

  return graphic
}

function drawExplorers(graphic, start, end, seed, progress) {
  drawExplorerFront(graphic, start, end, seed, progress, 0)
  drawExplorerFront(graphic, end, start, seed + 3701, progress, 2)
}

function drawExplorerFront(graphic, start, end, seed, progress, indexOffset) {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const distance = Math.max(1, Math.hypot(dx, dy))
  const normal = {x: -dy / distance, y: dx / distance}
  const reach = Math.min(1, progress * 1.08)
  const convergence = Math.max(0, Math.min(1, (progress - .48) / .42))
  const settling = Math.max(0, Math.min(1, (progress - .58) / .42))

  for (let localIndex = 0; localIndex < 2; localIndex++) {
    const index = localIndex + indexOffset
    const direction = index % 2 === 0 ? 1 : -1
    const spread = (18 + random(seed, 700 + index) * 42) * direction * (1 - convergence)
    const probeEnd = {
      x: start.x + dx * reach + normal.x * spread * Math.sin(Math.PI * reach),
      y: start.y + dy * reach + normal.y * spread * Math.sin(Math.PI * reach),
    }
    const probeSeed = seed + 900 + index * 71
    const probeOffset = (index - 1.5) * 3
    const probeProgress = Math.min(1, progress * 1.7)
    const path = organicPath(start, probeEnd, probeSeed, probeOffset)
    drawPartialPath(graphic, path, probeProgress)
    const survival = index === 0 ? 1 - settling * .58 : 1 - settling
    const explorerAlpha = (.2 + convergence * .16) * survival
    graphic.stroke({color: index === 0 ? 0xe7fac9 : 0x91ac78, width: index === 0 ? 1.05 : .55, alpha: explorerAlpha})
    const tip = pointOnOrganicPath(start, probeEnd, probeSeed, probeOffset, probeProgress)
    const pulseSpeed = 650 + random(probeSeed, 6) * 850
    graphic.circle(tip.x, tip.y, 1.5 + Math.sin(Date.now() / pulseSpeed + index) * .45).fill({color: 0xe5fac4, alpha: .55 * survival})
  }
}

function drawBidirectionalVariablePath(graphic, path, progress, style) {
  if (path.length < 3 || progress <= 0) return
  const midpoint = Math.floor((path.length - 1) / 2)
  const fromStart = path.slice(0, midpoint + 1)
  const fromEnd = path.slice(midpoint).reverse()
  drawVariablePath(graphic, fromStart, progress, style)
  drawVariablePath(graphic, fromEnd, progress, {...style, seed: style.seed + 389})
}

function visualDetail(nodeCount, routeCount) {
  if (routeCount > 120 || nodeCount > 45) {
    return {routeBranches: 3, matureBranches: 3, nodeFilaments: 6}
  }
  if (routeCount > 60 || nodeCount > 25) {
    return {routeBranches: 5, matureBranches: 5, nodeFilaments: 8}
  }
  return {routeBranches: 8, matureBranches: 9, nodeFilaments: 11}
}

function drawNode(app, item, detail, presence = 1, lifecycle = 1, withdrawing = false) {
  const x = item.x * app.screen.width
  const y = item.y * app.screen.height
  const fullRadius = Math.max(8, Math.min(app.screen.width, app.screen.height) * .014 * item.size)
  const radius = fullRadius * (.38 + presence * .62)
  const color = parseColor(item.color)
  const graphic = new Graphics()
  const now = Date.now()

  for (let index = 0; index < detail.nodeFilaments; index++) {
    const seed = item.id * 1907 + index * 149
    const angle = random(seed, 1) * Math.PI * 2
    const lifePeriod = 13000 + random(seed, 12) * 24000
    const lifePhase = random(seed, 13) * Math.PI * 2
    const livingReach = .82 + (.5 + Math.sin(now / lifePeriod * Math.PI * 2 + lifePhase) * .5) * .18
    const extension = .9 + Math.sin(now / (lifePeriod * .73) * Math.PI * 2 + lifePhase) * .1
    const filamentLength = fullRadius * (2.4 + random(seed, 2) * 3.8) * extension
    const stagger = index / Math.max(1, detail.nodeFilaments) * .56
    const lifecycleGrowth = withdrawing
      ? Math.max(0, Math.min(1, lifecycle * (.78 + random(seed, 14) * .22)))
      : Math.max(0, Math.min(1, (lifecycle - stagger) / .44))
    const growth = lifecycleGrowth * livingReach
    const start = {
      x: x + Math.cos(angle) * radius * .45,
      y: y + Math.sin(angle) * radius * .45,
    }
    const end = {
      x: x + Math.cos(angle) * filamentLength,
      y: y + Math.sin(angle) * filamentLength,
    }
    const path = organicPath(start, end, seed, (random(seed, 3) - .5) * radius * .65, 18)
    drawVariablePath(graphic, path, growth, {
      color: index % 3 === 0 ? color : 0xa8bd96,
      width: .34 + random(seed, 4) * .4,
      alpha: (.16 + random(seed, 5) * .16) * presence,
      seed,
      cord: false,
      tipTaper: true,
    })

    if (growth > .04) {
      const tip = pointOnOrganicPath(start, end, seed, (random(seed, 3) - .5) * radius * .65, growth)
      const pulse = .72 + Math.sin(now / (850 + random(seed, 15) * 1300) + lifePhase) * .22
      graphic.circle(tip.x, tip.y, .75 + pulse * .55).fill({color: 0xe8f5d8, alpha: (.16 + pulse * .16) * presence})
    }
  }

  return graphic
    .circle(x, y, radius * 3.6).fill({color, alpha: .035 * presence})
    .circle(x, y, radius * 1.55).stroke({color: parseColor(item.color), width: .7, alpha: .26 * presence})
    .circle(x, y, radius).fill({color, alpha: .58 * presence})
    .circle(x, y, radius * .72).stroke({color: 0xeaffd2, width: 1, alpha: .32 * presence})
    .circle(x - radius * .24, y - radius * .28, radius * .22).fill({color: 0xffffff, alpha: .5 * presence})
}

function organicPath(start, end, seed, offset, count = 72) {
  const points = []
  for (let index = 0; index <= count; index++) points.push(pointOnOrganicPath(start, end, seed, offset, index / count))
  return points
}

function pointOnOrganicPath(start, end, seed, offset, t) {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.max(1, Math.hypot(dx, dy))
  const normalX = -dy / length
  const normalY = dx / length
  const envelope = Math.sin(Math.PI * t)
  const amplitude = Math.min(34, length * .13)
  const phaseA = random(seed, 1) * Math.PI * 2
  const phaseB = random(seed, 2) * Math.PI * 2
  const wave = Math.sin(t * Math.PI * (2.2 + random(seed, 3) * 2.4) + phaseA) * .68 + Math.sin(t * Math.PI * 8.5 + phaseB) * .18
  const displacement = envelope * (wave * amplitude + offset)
  return {x: start.x + dx * t + normalX * displacement, y: start.y + dy * t + normalY * displacement}
}

function drawPartialPath(graphic, path, progress) {
  if (progress <= 0) return
  const scaled = Math.min(1, progress) * (path.length - 1)
  const complete = Math.floor(scaled)
  const fraction = scaled - complete
  graphic.moveTo(path[0].x, path[0].y)
  for (let index = 1; index <= complete; index++) graphic.lineTo(path[index].x, path[index].y)
  if (complete < path.length - 1 && fraction > 0) {
    const from = path[complete]
    const to = path[complete + 1]
    graphic.lineTo(from.x + (to.x - from.x) * fraction, from.y + (to.y - from.y) * fraction)
  }
}

function drawVariablePath(graphic, path, progress, style) {
  if (progress <= 0) return
  const scaled = Math.min(1, progress) * (path.length - 1)
  const complete = Math.floor(scaled)
  const fraction = scaled - complete
  const phaseA = random(style.seed, 41) * Math.PI * 2
  const phaseB = random(style.seed, 42) * Math.PI * 2
  const frequency = 1.4 + random(style.seed, 43) * 2.7
  const lifeSeed = style.lifeSeed ?? style.seed
  const breathPeriod = 9000 + random(lifeSeed, 44) * 18000
  const breathPhase = random(lifeSeed, 45) * Math.PI * 2
  const breathWaves = 1.1 + random(lifeSeed, 46) * 1.8
  const breathDirection = random(lifeSeed, 47) > .5 ? 1 : -1
  const breathAmount =
    style.breathe === false
      ? 0
      : style.cord
        ? .1 + random(lifeSeed, 48) * .08
        : .055 + random(lifeSeed, 48) * .065

  const strokeSegment = (from, to, t) => {
    const broadShape = style.tipTaper
      ? Math.max(.2, 1 - Math.pow(t, .78) * .8)
      : .74 + Math.pow(Math.sin(Math.PI * t), .65) * .34
    const variation =
      1 + Math.sin(t * Math.PI * 2 * frequency + phaseA) * (style.cord ? .25 : .16) +
      Math.sin(t * Math.PI * 11 + phaseB) * (style.cord ? .1 : .06)
    const breath = Math.sin(
      Date.now() / breathPeriod * Math.PI * 2 * breathDirection + breathPhase + t * Math.PI * 2 * breathWaves
    )
    const livingWidth = 1 + breath * breathAmount
    const width = Math.max(.22, style.width * broadShape * variation * livingWidth)
    const localAlpha = style.alpha * (.9 + Math.sin(t * Math.PI * 4 + phaseB) * .1) * (1 + breath * .035)
    graphic.moveTo(from.x, from.y).lineTo(to.x, to.y)
    graphic.stroke({color: style.color, width, alpha: localAlpha})
  }

  for (let index = 1; index <= complete; index++) {
    strokeSegment(path[index - 1], path[index], (index - .5) / (path.length - 1))
  }

  if (complete < path.length - 1 && fraction > 0) {
    const from = path[complete]
    const next = path[complete + 1]
    const to = {x: from.x + (next.x - from.x) * fraction, y: from.y + (next.y - from.y) * fraction}
    strokeSegment(from, to, (complete + fraction * .5) / (path.length - 1))
  }
}

function drawAdaptiveMaturation(graphic, start, end, seed, matureAgeMs, densityRank, branchLimit) {
  // Each new stage takes roughly twice as long as the previous one. The colony
  // therefore keeps exploring throughout an installation without growing at an
  // unbounded constant rate.
  const densitySlowdown = 1 + Math.log2(2 + densityRank) * .42
  const stage = Math.min(28.999, Math.log2(1 + matureAgeMs / (18000 * densitySlowdown)))
  const completeStages = Math.floor(stage)
  const activeProgress = stage - completeStages
  const visibleStages = Math.min(branchLimit, completeStages + (activeProgress > 0 ? 1 : 0))
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.max(1, Math.hypot(dx, dy))
  const normal = {x: -dy / length, y: dx / length}

  for (let index = 0; index < visibleStages; index++) {
    const progress = index < completeStages ? 1 : activeProgress
    if (progress <= 0) continue
    const anchorT = .08 + random(seed, 1200 + index) * .84
    const anchor = pointOnOrganicPath(start, end, seed + 97, 0, anchorT)
    const direction = random(seed, 1300 + index) > .5 ? 1 : -1
    const branchLength = 26 + random(seed, 1400 + index) * 76
    const along = (random(seed, 1500 + index) - .5) * branchLength * .7
    const tip = {
      x: anchor.x + normal.x * branchLength * direction + dx / length * along,
      y: anchor.y + normal.y * branchLength * direction + dy / length * along,
    }
    const path = organicPath(anchor, tip, seed + 1600 + index * 89, (random(seed, 1700 + index) - .5) * 8, 24)
    drawVariablePath(graphic, path, progress, {
      color: index % 3 === 0 ? 0xc2d5aa : 0x8fa57d,
      width: .4 + random(seed, 1800 + index) * .46,
      alpha: .2 + random(seed, 1900 + index) * .18,
      seed: seed + 2000 + index * 71,
      cord: false,
      tipTaper: true,
      breathe: false,
    })

    if (progress > .82) {
      const branchPoint = path[Math.floor(path.length * (.42 + random(seed, 2100 + index) * .3))]
      const forkLength = 7 + random(seed, 2200 + index) * 18
      const forkTip = {
        x: branchPoint.x + normal.x * forkLength * -direction,
        y: branchPoint.y + normal.y * forkLength * -direction,
      }
      const fork = organicPath(branchPoint, forkTip, seed + 2300 + index * 53, 2, 14)
      drawVariablePath(graphic, fork, Math.min(1, (progress - .82) / .18), {
        color: 0x8da17d,
        width: .38,
        alpha: .18,
        seed: seed + 2400 + index,
        cord: false,
        tipTaper: true,
        breathe: false,
      })
    }
  }
}

function dominanceForRoute(seed, distance, localReach) {
  const efficiency = Math.max(0, Math.min(1, 1 - distance / localReach))
  return Math.max(.08, Math.min(.95, .12 + efficiency * .63 + random(seed, 3050) * .3))
}

function remodelingStrength(seed, matureAgeMs, salt, dominance = .5) {
  if (matureAgeMs <= 0) return 1
  const adaptation = 1 - Math.exp(-matureAgeMs / 28000)
  const individualBias = (random(seed, salt + 1) - .5) * .12
  const establishedStrength = .62 + dominance * .58 + individualBias
  const demandPeriod = 45000 + random(seed, salt) * 65000
  const demandPhase = matureAgeMs / demandPeriod + random(seed, salt + 2)
  const demandEpoch = Math.floor(demandPhase)
  const demandFraction = demandPhase - demandEpoch
  const easedDemand = demandFraction * demandFraction * (3 - 2 * demandFraction)
  const previousDemand = .42 + random(seed, salt + 10 + demandEpoch * 2) * 1.1
  const nextDemand = .42 + random(seed, salt + 11 + demandEpoch * 2) * 1.1
  const changingDemand = previousDemand + (nextDemand - previousDemand) * easedDemand
  const structuralTarget = establishedStrength * .42 + changingDemand * .58
  const finePulsePeriod = 18000 + random(seed, salt + 3) * 24000
  const finePulse = Math.sin(matureAgeMs / finePulsePeriod * Math.PI * 2 + random(seed, salt + 4) * Math.PI * 2) * .06
  return Math.max(.2, 1 + (structuralTarget - 1) * adaptation + finePulse * adaptation)
}

function drawSideHyphae(graphic, start, end, seed, progress, centerPathSeed, branchCount) {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.max(1, Math.hypot(dx, dy))
  const normal = {x: -dy / length, y: dx / length}

  for (let index = 0; index < branchCount; index++) {
    const originT = .09 + random(seed, 100 + index) * .78
    if (progress <= originT) continue
    const localProgress = Math.min(1, (progress - originT) / (.13 + random(seed, 150 + index) * .12))
    const origin = pointOnOrganicPath(start, end, centerPathSeed, 0, originT)
    const direction = random(seed, 200 + index) > .5 ? 1 : -1
    const branchLifePeriod = 16000 + random(seed, 270 + index) * 30000
    const branchLifePhase = random(seed, 280 + index) * Math.PI * 2
    const branchLife = .9 + Math.sin(Date.now() / branchLifePeriod * Math.PI * 2 + branchLifePhase) * .11
    const branchLength = (24 + random(seed, 300 + index) * 68) * branchLife
    const along = (random(seed, 400 + index) - .5) * branchLength * .55
    const tip = {x: origin.x + normal.x * branchLength * direction + dx / length * along, y: origin.y + normal.y * branchLength * direction + dy / length * along}
    const branchSeed = seed + 9000 + index * 73
    const branchPath = organicPath(origin, tip, branchSeed, (random(branchSeed, 1) - .5) * 8, 22)
    drawVariablePath(graphic, branchPath, localProgress, {
      color: index % 3 === 0 ? 0xb5cba0 : 0x879d78,
      width: .4 + random(branchSeed, 2) * .42,
      alpha: .22 + random(branchSeed, 3) * .18,
      seed: branchSeed,
      cord: false,
      tipTaper: true,
    })

    if (localProgress > .62 && random(branchSeed, 4) > .46) {
      const forkT = .38 + random(branchSeed, 5) * .3
      const forkOrigin = pointOnOrganicPath(origin, tip, branchSeed, 0, forkT)
      const forkLength = branchLength * (.28 + random(branchSeed, 6) * .34)
      const forkDirection = random(branchSeed, 7) > .5 ? 1 : -1
      const forkTip = {
        x: forkOrigin.x + normal.x * forkLength * direction * forkDirection + dx / length * forkLength * .35,
        y: forkOrigin.y + normal.y * forkLength * direction * forkDirection + dy / length * forkLength * .35,
      }
      const forkSeed = branchSeed + 4300
      const forkPath = organicPath(forkOrigin, forkTip, forkSeed, (random(forkSeed, 1) - .5) * 5, 14)
      drawVariablePath(graphic, forkPath, Math.min(1, (localProgress - .62) / .38), {
        color: 0x819574,
        width: .32 + random(forkSeed, 2) * .24,
        alpha: .16 + random(forkSeed, 3) * .14,
        seed: forkSeed,
        cord: false,
        tipTaper: true,
        breathe: false,
      })
    }

    if (localProgress > .8) {
      const tipPulse = .72 + Math.sin(Date.now() / (900 + random(branchSeed, 8) * 1700)) * .28
      graphic.circle(tip.x, tip.y, .7 + tipPulse * .42).fill({color: 0xd9edbd, alpha: .18 + tipPulse * .16})

      const signalCycle = (Date.now() / (8500 + random(branchSeed, 9) * 12000) + random(branchSeed, 10)) % 1
      const signalT = Math.min(localProgress, .08 + signalCycle * .84)
      const signal = pointOnOrganicPath(origin, tip, branchSeed, (random(branchSeed, 1) - .5) * 8, signalT)
      const signalGlow = .65 + Math.sin(Date.now() / 720 + branchLifePhase) * .25
      graphic.circle(signal.x, signal.y, 1.05 + signalGlow * .5).fill({color: 0xf0ffe0, alpha: .18 + signalGlow * .22})
    }
  }
}

function drawFusionLoops(graphic, start, end, seed, progress, centerPathSeed) {
  for (let index = 0; index < 3; index++) {
    const fromT = .18 + index * .2 + random(seed, 510 + index) * .06
    const toT = Math.min(.93, fromT + .12 + random(seed, 520 + index) * .13)
    if (progress < toT) continue
    const from = pointOnOrganicPath(start, end, centerPathSeed, 0, fromT)
    const to = pointOnOrganicPath(start, end, centerPathSeed, 0, toT)
    const dx = to.x - from.x
    const dy = to.y - from.y
    const length = Math.max(1, Math.hypot(dx, dy))
    const direction = random(seed, 530 + index) > .5 ? 1 : -1
    const control = {x: (from.x + to.x) / 2 - dy / length * (10 + random(seed, 540 + index) * 16) * direction, y: (from.y + to.y) / 2 + dx / length * (10 + random(seed, 540 + index) * 16) * direction}
    graphic.moveTo(from.x, from.y).quadraticCurveTo(control.x, control.y, to.x, to.y)
    graphic.stroke({color: 0xc8d2bb, width: .55, alpha: .24})
  }
}

function drawFrontierLife(graphic, app, placed, connections, now, serverClockOffset) {
  const connected = new Set()
  for (const edge of connections) { connected.add(edge.source_id); connected.add(edge.target_id) }
  const center = {x: app.screen.width / 2, y: app.screen.height / 2}

  for (const item of placed.values()) {
    const origin = {x: item.x * app.screen.width, y: item.y * app.screen.height}
    const away = Math.atan2(origin.y - center.y, origin.x - center.x)
    const breath = .5 + .5 * Math.sin(now / 1700 + item.id)
    const placedAt = Date.parse(item.updated_at)
    const arrival = Number.isFinite(placedAt)
      ? Math.max(0, Math.min(1, (now + serverClockOffset - placedAt) / 7000))
      : 1
    graphic.circle(origin.x, origin.y, 18 + breath * 7).stroke({color: 0xe8eadf, width: .55, alpha: (.07 + breath * .09) * arrival})
    const tips = connected.has(item.id) ? 3 : 5
    for (let index = 0; index < tips; index++) {
      const seed = item.id * 977 + index * 131
      const cycle = (now / (14000 + random(seed, 1) * 26000) + random(seed, 2)) % 1
      const rawGrowth =
        cycle < .56
          ? cycle / .56
          : cycle < .7
            ? 1
            : 1 - (cycle - .7) / .3
      const easedGrowth = rawGrowth * rawGrowth * (3 - 2 * rawGrowth)
      const growth = easedGrowth * arrival
      const fade = Math.max(0, Math.min(1, rawGrowth))
      const angle = away + (random(seed, 3) - .5) * 2.8
      const length = (18 + random(seed, 4) * 46) * growth
      const end = {x: origin.x + Math.cos(angle) * length, y: origin.y + Math.sin(angle) * length}
      const path = organicPath(origin, end, seed, (random(seed, 5) - .5) * 9, 18)
      drawPartialPath(graphic, path, 1)
      graphic.stroke({color: 0xe0e4d8, width: .55, alpha: (.08 + fade * .3) * fade * arrival})
      if (growth > .15) graphic.circle(end.x, end.y, 1.35).fill({color: 0xfffceb, alpha: fade * .52})
    }
  }
}

function drawResourceFlow(graphic, app, placed, connections, now, serverClockOffset) {
  for (const edge of connections) {
    const source = placed.get(edge.source_id)
    const target = placed.get(edge.target_id)
    if (!source || !target) continue
    const startedAt = Date.parse(edge.growth_started_at)
    if (now + serverClockOffset - startedAt < edge.growth_duration_ms) continue
    const start = {x: target.x * app.screen.width, y: target.y * app.screen.height}
    const end = {x: source.x * app.screen.width, y: source.y * app.screen.height}
    for (let index = 0; index < 2; index++) {
      const travelDuration = 18000 + random(edge.path_seed, 810 + index) * 32000 + index * 4500
      let t = (now / travelDuration + random(edge.path_seed, 800 + index)) % 1
      if (index === 1) t = 1 - t
      const point = pointOnOrganicPath(start, end, edge.path_seed + 97, 0, t)
      const alpha = Math.sin(Math.PI * t) * .42
      graphic.circle(point.x, point.y, 5).fill({color: index === 0 ? 0xfff4c9 : 0xdde7dc, alpha: alpha * .11})
      graphic.circle(point.x, point.y, 1.55).fill({color: index === 0 ? 0xfff7dd : 0xf0f4e8, alpha: Math.min(.7, alpha * 1.35)})
    }
  }
}

function random(seed, salt) {
  const value = Math.sin((Number(seed) + Number(salt) * 101.37) * 12.9898) * 43758.5453
  return value - Math.floor(value)
}

function parseColor(value) {
  const parsed = Number.parseInt(String(value || "#d8e7b0").replace("#", ""), 16)
  return Number.isFinite(parsed) ? parsed : 0xd8e7b0
}
