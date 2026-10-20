import {gsap} from "gsap"
import {Application, Assets, Container, Graphics, Sprite} from "pixi.js"
import {observeSize} from "./dom.js"

const MOMENT_LIMIT = 16
const ARTWORK_LIMIT = 18
const RIBBON_COUNT = 3
const RECOMPOSE_INTERVAL = 50
const FEATURE_INTERVAL = 10
const ARTWORK_SLOTS = [
  [0.16, 0.2], [0.39, 0.17], [0.68, 0.21], [0.86, 0.36],
  [0.72, 0.53], [0.38, 0.46], [0.13, 0.59], [0.34, 0.72],
  [0.65, 0.75], [0.87, 0.68], [0.57, 0.88], [0.2, 0.87],
]

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
const lerp = (from, to, amount) => from + (to - from) * amount

function seeded(index, salt = 0) {
  const value = Math.sin((index + 1) * 91.345 + salt * 17.137) * 43758.5453
  return value - Math.floor(value)
}

function clearContainer(container) {
  for (const child of container.removeChildren()) child.destroy({children: true})
}

function fitTexture(sprite, texture, width, height) {
  const scale = Math.max(width / Math.max(1, texture.width), height / Math.max(1, texture.height))
  sprite.scale.set(scale)
}

function createMomentCard(item, texture, width, height, index) {
  const card = new Container()
  const shadow = new Graphics().roundRect(-width / 2 + 7, -height / 2 + 9, width, height, 4).fill({color: 0x28190f, alpha: 0.22})
  const paper = new Graphics().roundRect(-width / 2 - 7, -height / 2 - 7, width + 14, height + 20, 5).fill({color: 0xf1e6d4, alpha: 0.92})
  const photograph = new Sprite(texture)
  photograph.anchor.set(0.5)
  fitTexture(photograph, texture, width, height)
  photograph.tint = 0xffffff
  const crop = new Graphics().rect(-width / 2, -height / 2, width, height).fill(0xffffff)
  photograph.mask = crop
  const indexMark = new Graphics().rect(-width / 2, height / 2 + 5, Math.max(12, width * 0.18), 2).fill({color: 0x8f6d50, alpha: 0.65})
  card.addChild(shadow, paper, photograph, crop, indexMark)
  card.wc = {item, index, photograph, width, height, phase: seeded(index, 2) * Math.PI * 2}
  return card
}

function assignMoment(card, item, texture, animate, track) {
  if (!item || !texture) {
    card.visible = false
    return
  }
  const changed = String(card.wc.item?.id) !== String(item.id)
  card.visible = true
  card.wc.item = item
  if (!changed) return
  card.wc.photograph.texture = texture
  fitTexture(card.wc.photograph, texture, card.wc.width, card.wc.height)
  if (animate) {
    card.alpha = 0
    card.wc.photograph.tint = 0x3c302c
    track(gsap.to(card, {alpha: 1, duration: 1.2, ease: "power2.out"}))
    track(gsap.to(card.wc.photograph, {tint: 0xffffff, duration: 2.2, delay: 0.3, ease: "sine.inOut"}))
  } else {
    card.alpha = 1
    card.wc.photograph.tint = 0xffffff
  }
}

function createRibbon(index, items, textures, screen) {
  const ribbon = new Container()
  const width = clamp(screen.width * (index === 1 ? 0.17 : 0.145), 150, index === 1 ? 290 : 245)
  const cardWidth = width - 38
  const cardHeight = cardWidth * (index === 1 ? 0.76 : 0.69)
  const gap = cardHeight + 54
  const requiredCards = Math.max(5, Math.ceil(screen.height * 1.7 / gap) + 2)
  const trackHeight = requiredCards * gap
  ribbon.addChild(new Graphics().roundRect(-width / 2, -screen.height, width, screen.height * 2, 8).fill({color: index === 1 ? 0xf0ddc0 : 0xd7c5a9, alpha: index === 1 ? 0.42 : 0.28}))
  const holes = new Graphics()
  for (let y = -screen.height; y < screen.height; y += 31) {
    holes.roundRect(-width / 2 + 7, y, 9, 16, 2)
    holes.roundRect(width / 2 - 16, y, 9, 16, 2)
  }
  holes.fill({color: 0x643f2c, alpha: 0.34})
  ribbon.addChild(holes)
  const cards = new Container()
  ribbon.addChild(cards)
  if (items.length) {
    for (let cardIndex = 0; cardIndex < requiredCards; cardIndex++) {
      const itemIndex = (cardIndex * 2 + index) % items.length
      const texture = textures[itemIndex]
      if (!texture) continue
      const card = createMomentCard(items[itemIndex], texture, cardWidth, cardHeight, cardIndex + index * 20)
      card.y = -trackHeight / 2 + cardIndex * gap
      card.rotation = (seeded(cardIndex, index) - 0.5) * 0.025
      cards.addChild(card)
    }
  }
  const positions = [0.13, 0.5, 0.87]
  const rotations = [-0.055, 0.025, 0.065]
  ribbon.position.set(screen.width * positions[index], screen.height / 2)
  ribbon.rotation = rotations[index]
  ribbon.alpha = index === 1 ? 0.96 : 0.84
  ribbon.wc = {index, cards, trackHeight, baseX: ribbon.x, baseRotation: ribbon.rotation, speed: [17, -13, 9][index], shiftX: 0, shiftRotation: 0}
  return ribbon
}

function slotPosition(index, step, screen) {
  const slot = ARTWORK_SLOTS[(index + step) % ARTWORK_SLOTS.length]
  const lap = Math.floor(index / ARTWORK_SLOTS.length)
  const lapX = lap ? (index % 2 ? -0.045 : 0.045) : 0
  const lapY = lap ? (index % 3 - 1) * 0.045 : 0
  return {
    x: screen.width * clamp(slot[0] + lapX, 0.08, 0.92),
    y: screen.height * clamp(slot[1] + lapY, 0.1, 0.9),
  }
}

function createArtwork(item, texture, index, screen, compositionStep = 0) {
  const artwork = new Container()
  const visual = new Container()
  const target = Math.min(screen.width, screen.height) * (0.2 + seeded(index, 4) * 0.1)
  const scale = target / Math.max(texture.width, texture.height, 1)
  const glowColor = index % 2 ? 0xffd05f : 0x75d5cf
  const glow = new Graphics()
    .ellipse(0, target * 0.04, target * 0.72, target * 0.57).fill({color: glowColor, alpha: 0.07})
    .ellipse(0, target * 0.04, target * 0.59, target * 0.46).fill({color: glowColor, alpha: 0.09})
    .ellipse(0, target * 0.04, target * 0.47, target * 0.36).fill({color: glowColor, alpha: 0.1})
  const shadow = new Sprite(texture)
  shadow.anchor.set(0.5)
  shadow.scale.set(scale)
  shadow.tint = 0x201517
  shadow.alpha = 0.24
  shadow.position.set(10, 16)
  const image = new Sprite(texture)
  image.anchor.set(0.5)
  image.scale.set(scale)
  visual.addChild(glow, shadow, image)
  artwork.addChild(visual)
  const position = slotPosition(index, compositionStep, screen)
  artwork.position.set(position.x, position.y)
  artwork.zIndex = 20 + index
  artwork.wc = {
    item, index, visual, baseX: position.x, baseY: position.y,
    baseRotation: (seeded(index, 9) - 0.5) * 0.22,
    phase: seeded(index, 11) * Math.PI * 2,
    driftX: 18 + seeded(index, 13) * 24,
    driftY: 12 + seeded(index, 15) * 22,
    heroMix: 0,
  }
  return artwork
}

function createBackdrop(screen) {
  const backdrop = new Container()
  const field = new Graphics().rect(0, 0, screen.width, screen.height).fill(0xa94736)
  const sun = new Graphics().circle(screen.width * 0.22, screen.height * 0.26, Math.max(screen.width, screen.height) * 0.34).fill({color: 0xf4b94f, alpha: 0.38})
  const pool = new Graphics().circle(screen.width * 0.78, screen.height * 0.72, Math.max(screen.width, screen.height) * 0.3).fill({color: 0x24576d, alpha: 0.46})
  const wash = new Graphics().rect(0, 0, screen.width, screen.height).fill({color: 0x20152a, alpha: 0.16})
  backdrop.addChild(field, sun, pool, wash)
  backdrop.wc = {sun, pool}
  return backdrop
}

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("living-film-collage")
  const app = new Application()
  await app.init({resizeTo: container, background: "#a94736", antialias: true, autoDensity: true, resolution: Math.min(window.devicePixelRatio || 1, 1.75)})
  container.appendChild(app.canvas)
  app.stage.sortableChildren = true

  const overlay = document.createElement("div")
  overlay.className = "living-film-collage__overlay"
  overlay.innerHTML = `<div class="living-film-collage__title"><span>Workshop in motion</span><strong></strong></div><div class="living-film-collage__credit" aria-live="polite"><span>Made in this workshop</span><strong></strong></div><div class="living-film-collage__edge"></div>`
  overlay.querySelector(".living-film-collage__title strong").textContent = initial.instanceName || "Living Film Collage"
  const credit = overlay.querySelector(".living-film-collage__credit")
  const creditName = credit.querySelector("strong")
  container.appendChild(overlay)

  const backgroundLayer = new Container()
  const ribbonsLayer = new Container()
  const artworkLayer = new Container()
  ribbonsLayer.zIndex = 5
  artworkLayer.zIndex = 20
  artworkLayer.sortableChildren = true
  app.stage.addChild(backgroundLayer, ribbonsLayer, artworkLayer)

  const animations = new Set()
  let snapshot = initial
  let generation = 0
  let destroyed = false
  let compositionTimer = null
  let featureTimer = null
  let featured = null
  let pendingFeatureId = null
  let compositionStep = 0
  let sceneWidth = 0
  let sceneHeight = 0
  let elapsed = 0

  function track(animation, onComplete) {
    animations.add(animation)
    animation.eventCallback("onComplete", () => {
      animations.delete(animation)
      onComplete?.()
    })
    animation.eventCallback("onInterrupt", () => animations.delete(animation))
    return animation
  }

  function recompose() {
    compositionStep = (compositionStep + 3) % ARTWORK_SLOTS.length
    ribbonsLayer.children.forEach((ribbon, index) => {
      track(gsap.to(ribbon.wc, {shiftX: (index - 1) * app.screen.width * 0.018, shiftRotation: (index - 1) * 0.012, duration: 5.5, ease: "sine.inOut"}))
    })
    const artworks = [...artworkLayer.children].sort((a, b) => a.wc.index - b.wc.index)
    artworks.forEach(artwork => {
      const target = slotPosition(artwork.wc.index, compositionStep, app.screen)
      track(gsap.to(artwork.wc, {baseX: target.x, baseY: target.y, duration: 6.5, ease: "sine.inOut"}))
    })
  }

  function armCompositionClock() {
    if (compositionTimer) window.clearInterval(compositionTimer)
    compositionTimer = window.setInterval(recompose, RECOMPOSE_INTERVAL * 1000)
  }

  function hideCredit() {
    track(gsap.to(credit, {autoAlpha: 0, y: 12, duration: 0.5, ease: "power2.in"}))
  }

  function showCredit(artwork) {
    const item = artwork.wc.item
    creditName.textContent = item.showAttribution && item.creatorName ? `Created by ${item.creatorName}` : item.title || "A new creation"
    gsap.set(credit, {autoAlpha: 0, y: 16})
    track(gsap.to(credit, {autoAlpha: 1, y: 0, duration: 0.9, delay: 0.35, ease: "power3.out"}))
  }

  function activateFeature(next) {
    if (!next || destroyed) return
    featured = next
    next.zIndex = 100
    artworkLayer.sortChildren()
    showCredit(next)
    track(gsap.to(next.wc, {heroMix: 1, duration: 1.8, ease: "power3.inOut"}))
  }

  function featureNext(preferredId) {
    const artworks = [...artworkLayer.children].sort((a, b) => a.wc.index - b.wc.index)
    if (!artworks.length || destroyed) return
    let next = preferredId ? artworks.find(artwork => String(artwork.wc.item.id) === String(preferredId)) : null
    if (!next) {
      const currentIndex = featured ? artworks.indexOf(featured) : -1
      next = artworks[(currentIndex + 1) % artworks.length]
    }
    pendingFeatureId = null
    if (featured && featured !== next) {
      const previous = featured
      hideCredit()
      track(gsap.to(previous.wc, {heroMix: 0, duration: 1.35, ease: "power3.inOut"}), () => {
        previous.zIndex = 20 + previous.wc.index
        artworkLayer.sortChildren()
        activateFeature(next)
      })
    } else {
      activateFeature(next)
    }
  }

  function armFeatureClock(immediate = false) {
    if (featureTimer) window.clearInterval(featureTimer)
    if (immediate) featureNext(pendingFeatureId)
    featureTimer = window.setInterval(() => featureNext(pendingFeatureId), FEATURE_INTERVAL * 1000)
  }

  function onVisibilityChange() {
    if (document.hidden) {
      if (featureTimer) window.clearInterval(featureTimer)
      if (compositionTimer) window.clearInterval(compositionTimer)
      featureTimer = null
      compositionTimer = null
      animations.forEach(animation => animation.pause())
    } else {
      animations.forEach(animation => animation.resume())
      armFeatureClock(false)
      armCompositionClock()
    }
  }

  async function buildRibbons(moments, textures) {
    clearContainer(ribbonsLayer)
    for (let index = 0; index < RIBBON_COUNT; index++) ribbonsLayer.addChild(createRibbon(index, moments, textures, app.screen))
  }

  async function fullBuild(next, expectedGeneration) {
    const moments = next.moments.slice(0, MOMENT_LIMIT)
    const artworks = next.artworks.slice(0, ARTWORK_LIMIT)
    const textures = await Promise.all([...moments, ...artworks].map(item => Assets.load(item.url).catch(() => null)))
    if (expectedGeneration !== generation || destroyed) return
    if (featureTimer) window.clearInterval(featureTimer)
    if (compositionTimer) window.clearInterval(compositionTimer)
    const featuredId = featured?.wc.item.id
    animations.forEach(animation => animation.kill())
    animations.clear()
    clearContainer(backgroundLayer)
    clearContainer(artworkLayer)
    backgroundLayer.addChild(createBackdrop(app.screen))
    await buildRibbons(moments, textures.slice(0, moments.length))
    artworks.forEach((item, index) => {
      const texture = textures[moments.length + index]
      if (!texture) return
      const artwork = createArtwork(item, texture, index, app.screen, compositionStep)
      artwork.alpha = 0
      artwork.scale.set(0.72)
      artworkLayer.addChild(artwork)
      track(gsap.to(artwork, {alpha: 1, duration: 0.75, delay: index * 0.04, ease: "power2.out"}))
      track(gsap.to(artwork.scale, {x: 1, y: 1, duration: 1, delay: index * 0.04, ease: "power3.out"}))
    })
    featured = null
    pendingFeatureId = featuredId || artworks[0]?.id || null
    sceneWidth = app.screen.width
    sceneHeight = app.screen.height
    armFeatureClock(true)
    armCompositionClock()
  }

  async function reconcileMoments(moments, expectedGeneration) {
    const textures = await Promise.all(moments.map(item => Assets.load(item.url).catch(() => null)))
    if (expectedGeneration !== generation || destroyed) return
    if (!ribbonsLayer.children.some(ribbon => ribbon.wc.cards.children.length) && moments.length) {
      await buildRibbons(moments, textures)
      return
    }
    const textureById = new Map(moments.map((item, index) => [String(item.id), textures[index]]))
    const itemById = new Map(moments.map(item => [String(item.id), item]))
    const cards = ribbonsLayer.children.flatMap(ribbon => ribbon.wc.cards.children)
    const counts = new Map()
    cards.forEach(card => {
      const id = String(card.wc.item?.id)
      if (itemById.has(id)) counts.set(id, (counts.get(id) || 0) + 1)
    })
    const represented = new Set(counts.keys())
    const missing = moments.filter(item => !represented.has(String(item.id)))
    const candidates = cards.filter(card => !itemById.has(String(card.wc.item?.id)))
    cards.forEach(card => {
      const id = String(card.wc.item?.id)
      if ((counts.get(id) || 0) > 1 && !candidates.includes(card)) {
        candidates.push(card)
        counts.set(id, counts.get(id) - 1)
      }
    })
    missing.forEach((item, index) => {
      const card = candidates.shift() || cards[index % Math.max(1, cards.length)]
      if (card) assignMoment(card, item, textureById.get(String(item.id)), true, track)
    })
    candidates.forEach((card, index) => {
      const item = moments[index % Math.max(1, moments.length)]
      assignMoment(card, item, item && textureById.get(String(item.id)), false, track)
    })
    cards.forEach(card => {
      const item = itemById.get(String(card.wc.item?.id))
      if (item) card.wc.item = item
      else if (!moments.length) card.visible = false
    })
  }

  async function reconcileArtworks(artworks, expectedGeneration) {
    const wanted = new Map(artworks.map(item => [String(item.id), item]))
    const existing = new Map(artworkLayer.children.map(artwork => [String(artwork.wc.item.id), artwork]))
    const missing = artworks.filter(item => !existing.has(String(item.id)))
    const textures = await Promise.all(missing.map(item => Assets.load(item.url).catch(() => null)))
    if (expectedGeneration !== generation || destroyed) return
    for (const artwork of [...artworkLayer.children]) {
      const item = wanted.get(String(artwork.wc.item.id))
      if (item) artwork.wc.item = item
      else {
        if (artwork === featured) featured = null
        artworkLayer.removeChild(artwork)
        artwork.destroy({children: true})
      }
    }
    const used = new Set(artworkLayer.children.map(artwork => artwork.wc.index))
    missing.forEach((item, position) => {
      const texture = textures[position]
      if (!texture) return
      let index = 0
      while (used.has(index)) index++
      used.add(index)
      const artwork = createArtwork(item, texture, index, app.screen, compositionStep)
      artwork.alpha = 0
      artwork.scale.set(0.08)
      artworkLayer.addChild(artwork)
      track(gsap.to(artwork, {alpha: 1, duration: 0.8, ease: "power2.out"}))
      track(gsap.to(artwork.scale, {x: 1, y: 1, duration: 1.8, ease: "elastic.out(1, 0.48)"}))
    })
    if (missing.length) pendingFeatureId = String(missing[0].id)
    if (!featured && artworkLayer.children.length) featureNext(pendingFeatureId)
  }

  async function render(next) {
    snapshot = next
    const current = ++generation
    await Promise.all([
      reconcileMoments(next.moments.slice(0, MOMENT_LIMIT), current),
      reconcileArtworks(next.artworks.slice(0, ARTWORK_LIMIT), current),
    ])
  }

  async function rebuildForSize(width, height) {
    if (Math.abs(width - sceneWidth) < 2 && Math.abs(height - sceneHeight) < 2) return
    const current = ++generation
    await fullBuild(snapshot, current)
  }

  app.ticker.add(ticker => {
    const seconds = Math.min(ticker.deltaMS / 1000, 0.05)
    elapsed += seconds
    ribbonsLayer.children.forEach(ribbon => {
      const data = ribbon.wc
      ribbon.x = data.baseX + data.shiftX
      ribbon.rotation = data.baseRotation + data.shiftRotation
      for (const card of data.cards.children) {
        card.y += data.speed * seconds
        if (data.speed > 0 && card.y > data.trackHeight / 2) card.y -= data.trackHeight
        if (data.speed < 0 && card.y < -data.trackHeight / 2) card.y += data.trackHeight
        card.x = Math.sin(elapsed * 0.28 + card.wc.phase) * 2.5
      }
    })
    artworkLayer.children.forEach(artwork => {
      const data = artwork.wc
      const freeX = data.baseX + Math.sin(elapsed * 0.26 + data.phase) * data.driftX
      const freeY = data.baseY + Math.cos(elapsed * 0.22 + data.phase) * data.driftY
      artwork.x = lerp(freeX, app.screen.width * 0.5, data.heroMix)
      artwork.y = lerp(freeY, app.screen.height * 0.5, data.heroMix)
      data.visual.rotation = lerp(data.baseRotation + Math.sin(elapsed * 0.22 + data.phase) * 0.035, 0, data.heroMix)
      data.visual.scale.set(1 + data.heroMix * 1.25)
    })
    const backdrop = backgroundLayer.children[0]
    if (backdrop?.wc) {
      backdrop.wc.sun.x = Math.sin(elapsed * 0.035) * app.screen.width * 0.025
      backdrop.wc.pool.x = Math.cos(elapsed * 0.028) * app.screen.width * 0.022
    }
  })

  const initialGeneration = ++generation
  await fullBuild(initial, initialGeneration)
  document.addEventListener("visibilitychange", onVisibilityChange)
  const stopResize = observeSize(container, rebuildForSize)

  return {
    update: render,
    resize: () => rebuildForSize(app.screen.width, app.screen.height),
    destroy() {
      destroyed = true
      generation++
      if (compositionTimer) window.clearInterval(compositionTimer)
      if (featureTimer) window.clearInterval(featureTimer)
      document.removeEventListener("visibilitychange", onVisibilityChange)
      animations.forEach(animation => animation.kill())
      animations.clear()
      stopResize()
      app.destroy(true, {children: true})
      overlay.remove()
      container.classList.remove("living-film-collage")
      container.replaceChildren()
    },
  }
}
