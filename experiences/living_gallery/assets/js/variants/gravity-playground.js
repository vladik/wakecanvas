import Matter from "matter-js"
import {Application, Assets, Container, Graphics, Sprite} from "pixi.js"
import {createAudioLevelInput} from "./audio-level-input.js"
import {observeSize} from "./dom.js"

const ARTWORK_LIMIT = 22
const MOMENT_LIMIT = 3
const MEMORY_POOL_LIMIT = 18
const BREATH_INTERVAL = 9
const MEMORY_INTERVAL = 10
const RAIN_INTERVAL = 1.7
const FEATURE_INTERVAL = 6.5
const {Bodies, Body, Composite, Constraint, Engine, Vector} = Matter

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
const mix = (from, to, amount) => from + (to - from) * amount
const hash = value => [...String(value)].reduce((sum, char) => ((sum * 33) ^ char.charCodeAt(0)) >>> 0, 5381)

function contain(texture, maximum) {
  const scale = maximum / Math.max(texture.width, texture.height, 1)
  return {width: texture.width * scale, height: texture.height * scale}
}

function destroyVisual(visual) {
  visual.destroy({children: true, texture: false, textureSource: false})
}

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("gravity-playground")

  const app = new Application()
  await app.init({resizeTo: container, background: "#15112a", antialias: true, autoDensity: true, resolution: Math.min(window.devicePixelRatio || 1, 1.65)})
  container.appendChild(app.canvas)

  function syncRendererSize(observedWidth, observedHeight) {
    const bounds = container.getBoundingClientRect()
    const width = observedWidth > 2 ? observedWidth : (bounds.width > 2 ? bounds.width : window.innerWidth)
    const height = observedHeight > 2 ? observedHeight : (bounds.height > 2 ? bounds.height : window.innerHeight)
    app.renderer.resize(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))
  }

  await new Promise(resolve => window.requestAnimationFrame(() => {
    syncRendererSize()
    resolve()
  }))

  const overlay = document.createElement("div")
  overlay.className = "gravity-playground__overlay"
  overlay.innerHTML = `<div class="gravity-playground__identity"><span>Every creation changes the balance</span><strong></strong></div><div class="gravity-playground__status"><i></i><span>The community is finding its balance</span></div><div class="gravity-playground__shade"></div>`
  overlay.querySelector(".gravity-playground__identity strong").textContent = initial.instanceName || "Gravity Playground"
  container.appendChild(overlay)
  const audio = createAudioLevelInput(container)

  const engine = Engine.create({enableSleeping: false})
  engine.gravity.y = 0.58
  engine.gravity.scale = 0.001
  const backgroundLayer = new Container()
  const momentLayer = new Container()
  const artworkLayer = new Container()
  artworkLayer.sortableChildren = true
  app.stage.addChild(backgroundLayer, momentLayer, artworkLayer)

  const artworks = new Map()
  const moments = new Map()
  let boundaries = []
  let destroyed = false
  let generation = 0
  let lastSoundBurst = 0
  let lastBreath = 0
  let lastMemoryChange = 0
  let lastRain = 0
  let rainIndex = 0
  let memoryOffset = 0
  let momentPool = []
  let momentSwapPending = false
  let featureElapsed = 0
  let featuredId = null
  let elapsed = 0
  const statusText = overlay.querySelector(".gravity-playground__status span")
  let statusResetTimer = null

  function announce(message, duration = 3600) {
    statusText.textContent = message
    if (statusResetTimer) window.clearTimeout(statusResetTimer)
    statusResetTimer = window.setTimeout(() => {
      statusText.textContent = "The community is finding its balance"
    }, duration)
  }

  function platformPosition(index) {
    const positions = [0.2, 0.5, 0.8]
    return {
      x: app.screen.width * positions[index % positions.length],
      y: app.screen.height * (index % 2 ? 0.57 : 0.68),
    }
  }

  function advanceFeature(preferredId) {
    const ids = [...artworks.keys()]
    if (!ids.length) {
      featuredId = null
      return
    }
    if (preferredId && artworks.has(String(preferredId))) {
      featuredId = String(preferredId)
    } else {
      const current = ids.indexOf(featuredId)
      featuredId = ids[(current + 1) % ids.length]
    }
    featureElapsed = 0
  }

  function rainNextArtwork() {
    const records = [...artworks.values()]
    if (!records.length) return
    let index = rainIndex % records.length
    let record = records[index]
    for (let attempt = 0; attempt < records.length; attempt++) {
      const candidateIndex = (rainIndex + attempt) % records.length
      const candidate = records[candidateIndex]
      if (!candidate.rainPhase && String(candidate.item.id) !== featuredId) {
        index = candidateIndex
        record = candidate
        break
      }
    }
    rainIndex++
    const platforms = [...moments.values()]
    const target = platforms[index % Math.max(1, platforms.length)]
    const seed = hash(record.item.id)
    const targetX = target
      ? target.body.position.x + ((seed % 100) / 100 - 0.5) * target.width * 0.52
      : app.screen.width * (0.16 + (seed % 680) / 1000)
    record.rainPhase = "out"
    record.rainProgress = 0
    record.rainTarget = {
      x: clamp(targetX, 70, app.screen.width - 70),
      velocityX: ((seed >> 5) % 30) / 45 - 0.33,
      angularVelocity: ((seed >> 8) % 20) / 900 - 0.011,
    }
    if (rainIndex % records.length === 1) announce("The artwork rain continues", 2200)
  }

  async function rotateMomentPhotos() {
    if (momentSwapPending || momentPool.length <= MOMENT_LIMIT) return
    momentSwapPending = true
    const currentGeneration = generation
    const step = 1 + Math.floor(Math.random() * Math.max(1, momentPool.length - 1))
    memoryOffset = (memoryOffset + step) % momentPool.length
    const records = [...moments.values()]
    const selections = records.map((_, index) => momentPool[(memoryOffset + index) % momentPool.length])
    const textures = await Promise.all(selections.map(item => Assets.load(item.url).catch(() => null)))
    if (!destroyed && currentGeneration === generation) {
      records.forEach((record, index) => {
        const texture = textures[index]
        if (!texture) return
        record.pendingItem = selections[index]
        record.pendingTexture = texture
        record.swapPhase = "out"
        record.swapProgress = 0
      })
    }
    momentSwapPending = false
  }

  function paintBackground() {
    backgroundLayer.removeChildren().forEach(child => child.destroy())
    const width = app.screen.width, height = app.screen.height
    const field = new Graphics().rect(0, 0, width, height).fill(0x15112a)
    const warm = new Graphics().circle(width * 0.2, height * 0.28, Math.max(width, height) * 0.38).fill({color: 0xb84e62, alpha: 0.18})
    const cool = new Graphics().circle(width * 0.78, height * 0.6, Math.max(width, height) * 0.4).fill({color: 0x357b91, alpha: 0.18})
    const floorGlow = new Graphics().ellipse(width * 0.5, height * 0.92, width * 0.75, height * 0.18).fill({color: 0xf2b35f, alpha: 0.09})
    backgroundLayer.addChild(field, warm, cool, floorGlow)
  }

  function rebuildBoundaries() {
    boundaries.forEach(body => Composite.remove(engine.world, body))
    const width = app.screen.width, height = app.screen.height
    boundaries = [
      Bodies.rectangle(width / 2, height + 42, width + 180, 84, {isStatic: true, restitution: 0.5, friction: 0.7}),
      Bodies.rectangle(width / 2, -72, width + 180, 84, {isStatic: true, restitution: 0.72}),
      Bodies.rectangle(-42, height / 2, 84, height * 2, {isStatic: true, restitution: 0.7}),
      Bodies.rectangle(width + 42, height / 2, 84, height * 2, {isStatic: true, restitution: 0.7}),
    ]
    Composite.add(engine.world, boundaries)
  }

  function createArtworkVisual(texture, index) {
    const size = contain(texture, clamp(Math.min(app.screen.width, app.screen.height) * (0.13 + (index % 4) * 0.012), 90, 190))
    const visual = new Container()
    const halo = new Graphics().roundRect(-size.width * 0.58, -size.height * 0.58, size.width * 1.16, size.height * 1.16, 22).fill({color: index % 2 ? 0xf3b45f : 0x62c3cb, alpha: 0.12})
    const shadow = new Sprite(texture)
    shadow.anchor.set(0.5)
    shadow.width = size.width
    shadow.height = size.height
    shadow.tint = 0x160f20
    shadow.alpha = 0.28
    shadow.position.set(8, 11)
    const sprite = new Sprite(texture)
    sprite.anchor.set(0.5)
    sprite.width = size.width
    sprite.height = size.height
    visual.addChild(halo, shadow, sprite)
    return {visual, width: size.width, height: size.height}
  }

  async function addArtwork(item, index, expectedGeneration) {
    const texture = await Assets.load(item.url).catch(() => null)
    if (!texture || destroyed || expectedGeneration !== generation || artworks.has(String(item.id))) return
    const created = createArtworkVisual(texture, index)
    const seed = hash(item.id)
    const platforms = [...moments.values()]
    const target = platforms[index % Math.max(1, platforms.length)]
    const x = target
      ? target.body.position.x + ((seed % 100) / 100 - 0.5) * target.width * 0.45
      : app.screen.width * (0.15 + (seed % 700) / 1000)
    const y = Math.max(created.height * 0.55 + 24, app.screen.height * (0.12 + (index % 3) * 0.07))
    const body = Bodies.rectangle(x, y, created.width * 0.82, created.height * 0.82, {
      restitution: 0.72,
      friction: 0.24,
      frictionAir: 0.006,
      density: 0.0012,
      chamfer: {radius: Math.min(created.width, created.height) * 0.18},
      angle: ((seed % 100) / 100 - 0.5) * 0.5,
    })
    Body.setAngularVelocity(body, ((seed >> 7) % 100) / 2400 - 0.02)
    created.visual.scale.set(0.12)
    created.visual.position.set(body.position.x, body.position.y)
    created.visual.rotation = body.angle
    artworkLayer.addChild(created.visual)
    Composite.add(engine.world, body)
    artworks.set(String(item.id), {
      item,
      body,
      visual: created.visual,
      arrival: 0,
      focus: 0,
      rainPhase: null,
      rainProgress: 0,
      rainVisibility: 1,
      rainTarget: null,
    })
    advanceFeature(item.id)
    announce("A new creation changes the balance")
  }

  async function addMoment(item, index, expectedGeneration) {
    const texture = await Assets.load(item.url).catch(() => null)
    if (!texture || destroyed || expectedGeneration !== generation || moments.has(String(item.id))) return
    const width = clamp(app.screen.width * 0.27, 190, 370)
    const height = width * 0.62
    const visual = new Container()
    const frame = new Graphics().roundRect(-width / 2 - 8, -height / 2 - 8, width + 16, height + 16, 12).fill({color: 0xf2e2c9, alpha: 0.32})
    const photo = new Sprite(texture)
    photo.anchor.set(0.5)
    const scale = Math.max(width / Math.max(1, texture.width), height / Math.max(1, texture.height))
    photo.scale.set(scale)
    photo.alpha = 0.62
    const crop = new Graphics().roundRect(-width / 2, -height / 2, width, height, 8).fill(0xffffff)
    photo.mask = crop
    visual.addChild(frame, photo, crop)
    const position = platformPosition(index)
    const visualOffset = height / 2 + 22
    const body = Bodies.rectangle(position.x, position.y, width, 26, {
      friction: 0.92,
      frictionAir: 0.055,
      restitution: 0.18,
      density: 0.006,
      chamfer: {radius: 8},
    })
    const anchorY = Math.max(70, position.y - height - 80)
    const anchorInset = width * 0.39
    const constraints = [
      Constraint.create({pointA: {x: position.x - anchorInset, y: anchorY}, bodyB: body, pointB: {x: -anchorInset, y: 0}, length: position.y - anchorY, stiffness: 0.018, damping: 0.08}),
      Constraint.create({pointA: {x: position.x + anchorInset, y: anchorY}, bodyB: body, pointB: {x: anchorInset, y: 0}, length: position.y - anchorY, stiffness: 0.018, damping: 0.08}),
    ]
    const cords = new Graphics()
    visual.alpha = 0
    momentLayer.addChild(cords, visual)
    Composite.add(engine.world, [body, ...constraints])
    moments.set(String(item.id), {
      item,
      index,
      body,
      visual,
      photo,
      cords,
      constraints,
      width,
      height,
      anchorInset,
      anchorY,
      visualOffset,
      alpha: 0,
      swapPhase: null,
      swapProgress: 0,
      pendingItem: null,
      pendingTexture: null,
    })
  }

  async function reconcile(next) {
    const current = ++generation
    const nextArtwork = next.artworks.slice(0, ARTWORK_LIMIT)
    momentPool = next.moments.slice(0, MEMORY_POOL_LIMIT)
    const nextMoments = momentPool.slice(0, MOMENT_LIMIT)
    const artworkIds = new Set(nextArtwork.map(item => String(item.id)))
    const momentIds = new Set(nextMoments.map(item => String(item.id)))

    for (const [id, record] of artworks) if (!artworkIds.has(id)) {
      Composite.remove(engine.world, record.body)
      artworkLayer.removeChild(record.visual)
      destroyVisual(record.visual)
      artworks.delete(id)
    }
    for (const [id, record] of moments) if (!momentIds.has(id)) {
      Composite.remove(engine.world, record.body)
      record.constraints.forEach(constraint => Composite.remove(engine.world, constraint))
      momentLayer.removeChild(record.cords)
      record.cords.destroy()
      momentLayer.removeChild(record.visual)
      destroyVisual(record.visual)
      moments.delete(id)
    }

    nextArtwork.forEach(item => { const record = artworks.get(String(item.id)); if (record) record.item = item })
    nextMoments.forEach(item => { const record = moments.get(String(item.id)); if (record) record.item = item })
    await Promise.all(nextMoments.map((item, index) => moments.has(String(item.id)) ? null : addMoment(item, index, current)))
    await Promise.all(nextArtwork.map((item, index) => artworks.has(String(item.id)) ? null : addArtwork(item, index, current)))
  }

  function resize(observedWidth, observedHeight) {
    syncRendererSize(observedWidth, observedHeight)
    paintBackground()
    rebuildBoundaries()
    for (const record of artworks.values()) {
      Body.setPosition(record.body, {
        x: clamp(record.body.position.x, 60, app.screen.width - 60),
        y: clamp(record.body.position.y, -200, app.screen.height - 80),
      })
    }
    for (const record of moments.values()) {
      const position = platformPosition(record.index)
      const anchorY = Math.max(70, position.y - record.visualOffset * 2 - 58)
      Body.setPosition(record.body, position)
      Body.setVelocity(record.body, {x: 0, y: 0})
      record.anchorY = anchorY
      record.constraints[0].pointA = {x: position.x - record.anchorInset, y: anchorY}
      record.constraints[1].pointA = {x: position.x + record.anchorInset, y: anchorY}
      record.constraints.forEach(constraint => { constraint.length = position.y - anchorY })
    }
  }

  const stopResize = observeSize(container, resize)
  resize()
  await reconcile(initial)
  resize()

  // The Experience stylesheet can finish applying after the renderer module mounts.
  // Repeat the same safe resize operation during that short startup window so bodies
  // are never created against a temporary 1x1 canvas.
  const startupResizeTimers = [80, 300, 900].map(delay => window.setTimeout(resize, delay))

  app.ticker.add(ticker => {
    const seconds = Math.min(ticker.deltaMS / 1000, 0.04)
    elapsed += seconds
    featureElapsed += seconds
    if (featureElapsed >= FEATURE_INTERVAL) advanceFeature()
    engine.gravity.x = 0
    engine.gravity.y = 0.58
    if (elapsed - lastBreath >= BREATH_INTERVAL) {
      lastBreath = elapsed
      announce("The shared canvas breathes", 2600)
      ;[...moments.values()].forEach((record, index) => {
        Body.applyForce(record.body, record.body.position, {x: (index % 2 ? -1 : 1) * 0.0011, y: -0.00045})
      })
    }
    if (elapsed - lastRain >= RAIN_INTERVAL) {
      lastRain = elapsed
      rainNextArtwork()
    }
    if (elapsed - lastMemoryChange >= MEMORY_INTERVAL) {
      lastMemoryChange = elapsed
      rotateMomentPhotos()
    }
    Engine.update(engine, seconds * 1000)
    const sound = audio.level()
    if (sound > 0.26 && elapsed - lastSoundBurst > 0.55) {
      lastSoundBurst = elapsed
      announce("The room shifts the balance", 2200)
      for (const record of moments.values()) Body.applyForce(record.body, record.body.position, {x: 0, y: -sound * 0.0012})
    }
    for (const record of artworks.values()) {
      if (record.rainPhase === "out") {
        record.rainProgress = Math.min(1, record.rainProgress + seconds / 0.48)
        record.rainVisibility = 1 - record.rainProgress
        if (record.rainProgress >= 1) {
          Body.setPosition(record.body, {x: record.rainTarget.x, y: 45})
          Body.setVelocity(record.body, {x: record.rainTarget.velocityX, y: 1.1})
          Body.setAngularVelocity(record.body, record.rainTarget.angularVelocity)
          record.rainPhase = "in"
          record.rainProgress = 0
        }
      } else if (record.rainPhase === "in") {
        record.rainProgress = Math.min(1, record.rainProgress + seconds / 0.68)
        record.rainVisibility = record.rainProgress
        if (record.rainProgress >= 1) {
          record.rainPhase = null
          record.rainTarget = null
          record.rainVisibility = 1
        }
      }
      record.arrival += (1 - record.arrival) * 0.07
      const featured = String(record.item.id) === featuredId
      record.focus += ((featured ? 1 : 0) - record.focus) * (featured ? 0.055 : 0.085)
      record.visual.position.set(
        mix(record.body.position.x, app.screen.width * 0.5, record.focus),
        mix(record.body.position.y, app.screen.height * 0.43, record.focus)
      )
      record.visual.rotation = mix(record.body.angle, 0, record.focus)
      const rainScale = 0.35 + record.rainVisibility * 0.65
      record.visual.scale.set(record.arrival * (1 + record.focus * 1.45) * rainScale)
      record.visual.alpha = record.rainVisibility
      record.visual.zIndex = featured || record.focus > 0.08 ? 100 : 0
    }
    for (const record of moments.values()) {
      record.alpha += (1 - record.alpha) * 0.035
      if (record.swapPhase === "out") {
        record.swapProgress = Math.min(1, record.swapProgress + seconds / 0.55)
        record.photo.alpha = 0.62 * (1 - record.swapProgress)
        record.visual.scale.set(1 - Math.sin(record.swapProgress * Math.PI) * 0.045)
        if (record.swapProgress >= 1) {
          record.item = record.pendingItem
          record.photo.texture = record.pendingTexture
          const scale = Math.max(record.width / Math.max(1, record.pendingTexture.width), record.height / Math.max(1, record.pendingTexture.height))
          record.photo.scale.set(scale)
          record.swapPhase = "in"
          record.swapProgress = 0
        }
      } else if (record.swapPhase === "in") {
        record.swapProgress = Math.min(1, record.swapProgress + seconds / 0.72)
        record.photo.alpha = 0.62 * record.swapProgress
        record.visual.scale.set(0.955 + record.swapProgress * 0.045)
        if (record.swapProgress >= 1) {
          record.swapPhase = null
          record.pendingItem = null
          record.pendingTexture = null
          record.photo.alpha = 0.62
          record.visual.scale.set(1)
        }
      }
      record.visual.position.set(
        record.body.position.x + Math.sin(record.body.angle) * record.visualOffset,
        record.body.position.y - Math.cos(record.body.angle) * record.visualOffset
      )
      record.visual.rotation = record.body.angle
      record.visual.alpha = record.alpha
      const left = Vector.rotate({x: -record.anchorInset, y: 0}, record.body.angle)
      const right = Vector.rotate({x: record.anchorInset, y: 0}, record.body.angle)
      record.cords.clear()
        .moveTo(record.constraints[0].pointA.x, record.constraints[0].pointA.y)
        .lineTo(record.body.position.x + left.x, record.body.position.y + left.y)
        .moveTo(record.constraints[1].pointA.x, record.constraints[1].pointA.y)
        .lineTo(record.body.position.x + right.x, record.body.position.y + right.y)
        .stroke({color: 0xe4c181, width: 2, alpha: 0.42})
    }
  })

  function onVisibilityChange() {
    if (document.hidden) app.ticker.stop()
    else app.ticker.start()
  }
  document.addEventListener("visibilitychange", onVisibilityChange)

  return {
    update: reconcile,
    resize,
    destroy() {
      destroyed = true
      generation++
      startupResizeTimers.forEach(timer => window.clearTimeout(timer))
      if (statusResetTimer) window.clearTimeout(statusResetTimer)
      document.removeEventListener("visibilitychange", onVisibilityChange)
      stopResize()
      audio.destroy()
      app.ticker.stop()
      for (const record of artworks.values()) destroyVisual(record.visual)
      for (const record of moments.values()) {
        destroyVisual(record.visual)
        record.cords.destroy()
      }
      artworks.clear()
      moments.clear()
      Composite.clear(engine.world, false, true)
      Engine.clear(engine)
      app.destroy(true, {children: true, texture: false, textureSource: false})
      overlay.remove()
      container.classList.remove("gravity-playground")
    },
  }
}
