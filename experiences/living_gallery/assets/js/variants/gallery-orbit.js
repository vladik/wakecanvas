import {gsap} from "gsap"
import * as THREE from "three"
import {observeSize} from "./dom.js"

const TAU = Math.PI * 2
const ARTWORK_LIMIT = 28
const MOMENT_LIMIT = 16
const FEATURE_INTERVAL = 10
const CINEMA_PHOTO_DURATION_MS = 10_000
const CINEMA_PLAYBACK_TIMEOUT_MS = 15_000

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
const lerp = (from, to, amount) => from + (to - from) * amount

function textureAspect(texture) {
  const image = texture?.image
  const width = image?.videoWidth || image?.naturalWidth || image?.width
  const height = image?.videoHeight || image?.naturalHeight || image?.height
  return width && height ? width / height : 4 / 3
}

function videoElement(texture) {
  const image = texture?.image
  return image instanceof HTMLVideoElement ? image : null
}

function releaseTexture(texture) {
  const video = videoElement(texture)
  if (video) {
    video.pause()
    video.removeAttribute("src")
    video.load()
  }
  texture?.dispose()
}

function loadVideoTexture(item) {
  return new Promise(resolve => {
    const video = document.createElement("video")
    video.muted = true
    video.defaultMuted = true
    video.volume = 0
    video.playsInline = true
    video.preload = "auto"
    video.disablePictureInPicture = true
    video.setAttribute("disableremoteplayback", "")

    let settled = false
    const timeout = window.setTimeout(() => finish(null), CINEMA_PLAYBACK_TIMEOUT_MS)

    function cleanup() {
      window.clearTimeout(timeout)
      video.removeEventListener("loadeddata", onLoaded)
      video.removeEventListener("error", onError)
    }

    function finish(texture) {
      if (settled) return
      settled = true
      cleanup()
      if (!texture) {
        video.removeAttribute("src")
        video.load()
      }
      resolve(texture)
    }

    function onLoaded() {
      video.pause()
      const texture = new THREE.VideoTexture(video)
      texture.colorSpace = THREE.SRGBColorSpace
      // requestVideoFrameCallback does not necessarily fire for a video that
      // was loaded and paused before its texture was created. Force the
      // decoded first frame into WebGL so the video has a visible orbit card.
      texture.needsUpdate = true
      finish(texture)
    }

    function onError() {
      finish(null)
    }

    video.addEventListener("loadeddata", onLoaded)
    video.addEventListener("error", onError)
    video.src = item.url
    video.load()
  })
}

function disposeObject(object) {
  object.traverse(child => {
    child.geometry?.dispose()
    if (Array.isArray(child.material)) {
      child.material.forEach(material => {
        releaseTexture(material.map)
        material.dispose()
      })
    } else {
      releaseTexture(child.material?.map)
      child.material?.dispose()
    }
  })
}

function nextFreeSlot(layer) {
  const used = new Set(layer.children.map(child => child.userData.slot))
  let slot = 0
  while (used.has(slot)) slot++
  return slot
}

function createMomentCard(item, texture, slot, focus = false, preserveAspect = false) {
  const aspect = preserveAspect
    ? clamp(textureAspect(texture), 0.5, 1.8)
    : clamp(textureAspect(texture), 0.72, 1.65)
  const height = 1.42
  const width = height * aspect
  const card = new THREE.Group()
  const backing = focus
    ? null
    : new THREE.Mesh(
        new THREE.PlaneGeometry(width + 0.16, height + 0.16),
        new THREE.MeshStandardMaterial({color: 0xe7dbc7, transparent: true, opacity: 0.3, roughness: 0.48, metalness: 0.12, side: THREE.DoubleSide})
      )
  if (backing) backing.position.z = -0.025
  const photograph = new THREE.Mesh(
    new THREE.PlaneGeometry(width, height),
    new THREE.MeshBasicMaterial({map: texture, color: focus ? 0xffffff : 0xb9c1c3, transparent: true, alphaTest: focus ? 0.015 : 0, opacity: focus ? 1 : 0.58, side: THREE.DoubleSide})
  )
  if (backing) card.add(backing)
  card.add(photograph)
  card.userData = {
    item,
    slot,
    kind: "moment",
    photograph,
    backing,
    focus,
    aspect,
    phase: slot * 0.71,
    arrival: 1,
    entranceMix: 0,
    heroMix: 0,
  }
  return card
}

function createArtwork(item, texture, slot, focus = false) {
  const aspect = clamp(textureAspect(texture), 0.58, 1.8)
  const height = 1.9
  const width = height * aspect
  const artwork = new THREE.Group()
  const halo = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 1.13, height * 1.13),
    new THREE.MeshBasicMaterial({color: 0xffd49a, transparent: true, opacity: focus ? 0 : 0.1, blending: THREE.AdditiveBlending, depthWrite: false})
  )
  halo.position.z = -0.045
  const image = new THREE.Mesh(
    new THREE.PlaneGeometry(width, height),
    new THREE.MeshBasicMaterial({map: texture, transparent: true, opacity: 1, side: THREE.DoubleSide, depthWrite: false})
  )
  artwork.add(halo, image)
  artwork.userData = {item, slot, kind: "artwork", image, halo, focus, aspect, heroMix: 0, arrival: 1, phase: slot * 0.83}
  return artwork
}

function createAtmosphere(scene) {
  const count = 260
  const positions = new Float32Array(count * 3)
  for (let index = 0; index < count; index++) {
    const radius = 4 + Math.random() * 11
    const angle = Math.random() * TAU
    positions[index * 3] = Math.cos(angle) * radius
    positions[index * 3 + 1] = (Math.random() - 0.5) * 14
    positions[index * 3 + 2] = Math.sin(angle) * radius - 2
  }
  const geometry = new THREE.BufferGeometry()
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))
  const points = new THREE.Points(geometry, new THREE.PointsMaterial({color: 0xffd8a3, size: 0.025, transparent: true, opacity: 0.38, depthWrite: false}))
  scene.add(points)
  return points
}

export async function mountWithOptions(container, initial, options = {}) {
  const focus = options.focus === true
  const cinema = options.cinema === true
  container.replaceChildren()
  container.classList.add("living-spiral")
  if (focus) container.classList.add("living-spiral--focus")
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false, powerPreference: "high-performance"})
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75))
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 0.92
  renderer.setClearColor(0x050609)
  container.appendChild(renderer.domElement)

  const overlay = document.createElement("div")
  overlay.className = "living-spiral__overlay"
  overlay.innerHTML = focus
    ? `<div class="living-spiral__identity"><span></span><strong></strong><small></small></div><div class="living-spiral__credit" aria-live="polite"><strong></strong><small></small></div><div class="living-spiral__vignette"></div><div class="living-spiral__grain"></div>`
    : `<div class="living-spiral__identity"><span>Living Gallery</span><strong></strong></div><div class="living-spiral__credit" aria-live="polite"><span>Now in the light</span><strong></strong></div><div class="living-spiral__vignette"></div><div class="living-spiral__grain"></div>`
  container.appendChild(overlay)
  const identity = overlay.querySelector(".living-spiral__identity")
  const identityLabel = identity.querySelector("span")
  const identityTitle = identity.querySelector("strong")
  const identityDescription = focus ? identity.querySelector("small") : null

  function setPresentation(context) {
    if (focus) {
      const label = context.presentationLabel?.trim() || ""
      const title = context.presentationTitle?.trim() || ""
      const description = context.presentationDescription?.trim() || ""
      identityLabel.textContent = label
      identityTitle.textContent = title
      identityDescription.textContent = description
      identityLabel.style.display = label === "" ? "none" : ""
      identityTitle.style.display = title === "" ? "none" : ""
      identityDescription.style.display = description === "" ? "none" : "block"
      identity.classList.toggle("living-spiral__identity--empty", label === "" && title === "" && description === "")
    } else {
      identityTitle.textContent = context.instanceName || "Workshop Moments"
    }
  }

  setPresentation(initial)
  const credit = overlay.querySelector(".living-spiral__credit")
  const creditName = credit.querySelector("strong")
  const creditCreator = focus ? credit.querySelector("small") : null

  const scene = new THREE.Scene()
  scene.fog = new THREE.FogExp2(0x050609, 0.047)
  const camera = new THREE.PerspectiveCamera(43, 1, 0.1, 80)
  camera.position.set(0, 0.2, 12.5)
  const momentLayer = new THREE.Group()
  const artworkLayer = new THREE.Group()
  scene.add(momentLayer, artworkLayer)
  scene.add(new THREE.HemisphereLight(0xffe8c7, 0x10182d, 1.45))
  const key = new THREE.PointLight(0xffb86b, 22, 24, 1.7)
  key.position.set(3.5, 4.5, 6)
  const blue = new THREE.PointLight(0x4979ff, 15, 20, 1.8)
  blue.position.set(-5, -3, 2)
  scene.add(key, blue)
  const atmosphere = createAtmosphere(scene)

  const loader = new THREE.TextureLoader()
  const clock = new THREE.Clock()
  const cameraTarget = new THREE.Vector3()
  const heroPosition = new THREE.Vector3(0, 0.05, 4.2)
  const momentOrbitEuler = new THREE.Euler()
  const momentOrbitQuaternion = new THREE.Quaternion()
  const tweens = new Set()
  let elapsed = 0
  let generation = 0
  let featureTimer = null
  let featured = null
  let pendingFeatureId = null
  let context = initial
  let cinemaTimer = null
  let cinemaFinishTimer = null
  let cinemaPlaybackTimer = null
  let cinemaCursor = 0
  let cinemaActive = false
  let focusedMoment = null
  let destroyed = false
  let firstRender = true
  let presentationPaused = false

  function track(animation, onComplete) {
    tweens.add(animation)
    if (presentationPaused) animation.pause()
    animation.eventCallback("onComplete", () => {
      tweens.delete(animation)
      onComplete?.()
    })
    animation.eventCallback("onInterrupt", () => tweens.delete(animation))
    return animation
  }

  function hideCredit() {
    track(gsap.to(credit, {autoAlpha: 0, y: 12, duration: 0.55, ease: "power2.in"}))
  }

  function setCreditContent(artwork) {
    const item = artwork.userData.item
    if (focus) {
      const title = item.title?.trim() || ""
      const creator = item.showAttribution && item.creatorName?.trim() ? `Created by ${item.creatorName.trim()}` : ""
      creditName.textContent = title
      creditCreator.textContent = creator
      creditName.style.display = title === "" ? "none" : ""
      creditCreator.style.display = creator === "" ? "none" : "block"
      const visible = title !== "" || creator !== ""
      credit.classList.toggle("living-spiral__credit--empty", !visible)
      return visible
    } else {
      creditName.textContent = item.showAttribution && item.creatorName ? `Created by ${item.creatorName}` : item.title || "A new creation"
      return true
    }
  }

  function showCredit(artwork) {
    if (!setCreditContent(artwork)) {
      gsap.set(credit, {autoAlpha: 0, y: 0})
      return
    }
    gsap.set(credit, {autoAlpha: 0, y: 16})
    track(gsap.to(credit, {autoAlpha: 1, y: 0, duration: 1, delay: 0.35, ease: "power3.out"}))
  }

  function activateFeature(next) {
    if (!next || destroyed || cinemaActive) return
    featured = next
    showCredit(next)
    track(gsap.to(next.userData, {heroMix: 1, duration: 2.1, ease: "power3.inOut"}))
  }

  function featureNext(preferredId) {
    if (cinemaActive) return
    const artworks = [...artworkLayer.children].sort((a, b) => a.userData.slot - b.userData.slot)
    if (!artworks.length || destroyed) return
    let next = preferredId ? artworks.find(artwork => artwork.userData.item.id === preferredId) : null
    if (!next) {
      const currentIndex = featured ? artworks.indexOf(featured) : -1
      next = artworks[(currentIndex + 1) % artworks.length]
    }
    pendingFeatureId = null
    if (featured && featured !== next) {
      const previous = featured
      hideCredit()
      track(gsap.to(previous.userData, {heroMix: 0, duration: 1.5, ease: "power3.inOut"}), () => activateFeature(next))
    } else {
      activateFeature(next)
    }
  }

  function armFeatureClock(immediate = false) {
    if (featureTimer) window.clearInterval(featureTimer)
    if (presentationPaused || document.hidden || cinemaActive) {
      featureTimer = null
      return
    }
    if (immediate) featureNext(pendingFeatureId)
    featureTimer = window.setInterval(() => featureNext(pendingFeatureId), FEATURE_INTERVAL * 1000)
  }

  function cinemaIntervalMs() {
    const seconds = Number(context.featuredIntervalSeconds || 180)
    return clamp(Number.isFinite(seconds) ? seconds : 180, 30, 3_600) * 1000
  }

  function featuredMomentCards() {
    if (!cinema) return []
    const featuredIds = new Set((context.featuredMoments || []).map(item => String(item.id)))
    return momentLayer.children
      .filter(card => featuredIds.has(String(card.userData.item.id)))
      .sort((a, b) => a.userData.slot - b.userData.slot)
  }

  function clearCinemaTimers() {
    window.clearTimeout(cinemaTimer)
    window.clearTimeout(cinemaFinishTimer)
    window.clearTimeout(cinemaPlaybackTimer)
    cinemaTimer = null
    cinemaFinishTimer = null
    cinemaPlaybackTimer = null
  }

  function scheduleCinema(delay = cinemaIntervalMs()) {
    window.clearTimeout(cinemaTimer)
    cinemaTimer = null
    if (!cinema || destroyed || cinemaActive || presentationPaused || document.hidden || featuredMomentCards().length === 0) return
    cinemaTimer = window.setTimeout(startCinemaFeature, delay)
  }

  function startCinemaFeature() {
    cinemaTimer = null
    const cards = featuredMomentCards()
    if (destroyed || cinemaActive || cards.length === 0) return

    focusedMoment = cards[cinemaCursor % cards.length]
    cinemaCursor = (cinemaCursor + 1) % cards.length
    cinemaActive = true
    if (featureTimer) window.clearInterval(featureTimer)
    featureTimer = null
    hideCredit()

    const bringMomentForward = () => {
      if (destroyed || !focusedMoment) return
      showCredit(focusedMoment)
      track(
        gsap.to(focusedMoment.userData, {heroMix: 1, duration: 2.1, ease: "power3.inOut"}),
        playFocusedMoment
      )
    }

    if (featured) {
      track(gsap.to(featured.userData, {heroMix: 0, duration: 1.5, ease: "power3.inOut"}), bringMomentForward)
    } else {
      bringMomentForward()
    }
  }

  function playFocusedMoment() {
    if (destroyed || !focusedMoment || !cinemaActive) return
    const video = videoElement(focusedMoment.userData.photograph.material.map)
    if (!video) {
      cinemaFinishTimer = window.setTimeout(finishCinemaFeature, CINEMA_PHOTO_DURATION_MS)
      return
    }

    video.currentTime = 0
    video.addEventListener("ended", finishCinemaFeature, {once: true})
    video.addEventListener("error", finishCinemaFeature, {once: true})
    cinemaPlaybackTimer = window.setTimeout(finishCinemaFeature, CINEMA_PLAYBACK_TIMEOUT_MS)
    video.play().then(() => {
      window.clearTimeout(cinemaPlaybackTimer)
      const durationMs = Number(focusedMoment?.userData.item.durationMs || video.duration * 1000)
      cinemaPlaybackTimer = window.setTimeout(
        finishCinemaFeature,
        Math.max(Number.isFinite(durationMs) ? durationMs + 30_000 : 0, 60_000)
      )
    }).catch(finishCinemaFeature)
  }

  function finishCinemaFeature() {
    if (!cinemaActive || destroyed || !focusedMoment) return
    clearCinemaTimers()
    const previous = focusedMoment
    const video = videoElement(previous.userData.photograph.material.map)
    video?.pause()
    hideCredit()

    track(gsap.to(previous.userData, {heroMix: 0, duration: 1.5, ease: "power3.inOut"}), () => {
      if (video) {
        video.currentTime = 0
        video.removeEventListener("ended", finishCinemaFeature)
        video.removeEventListener("error", finishCinemaFeature)
      }
      focusedMoment = null
      cinemaActive = false
      featureNext()
      armFeatureClock(false)
      scheduleCinema()
    })
  }

  function onVisibilityChange() {
    if (document.hidden) {
      if (featureTimer) window.clearInterval(featureTimer)
      featureTimer = null
      clearCinemaTimers()
      if (focusedMoment) videoElement(focusedMoment.userData.photograph.material.map)?.pause()
      tweens.forEach(animation => animation.pause())
    } else if (!presentationPaused) {
      tweens.forEach(animation => animation.resume())
      if (cinemaActive && focusedMoment?.userData.heroMix > 0.98) {
        const video = videoElement(focusedMoment.userData.photograph.material.map)
        if (video) video.play().catch(finishCinemaFeature)
        else cinemaFinishTimer = window.setTimeout(finishCinemaFeature, CINEMA_PHOTO_DURATION_MS)
      } else if (!cinemaActive) {
        armFeatureClock(false)
        scheduleCinema()
      }
    }
  }

  async function reconcileLayer(layer, items, create, animateNew, expectedGeneration) {
    const wanted = new Map(items.map(item => [String(item.id), item]))
    const existing = new Map(layer.children.map(child => [String(child.userData.item.id), child]))
    const missing = items.filter(item => !existing.has(String(item.id)))
    const loaded = await Promise.all(
      missing.map(item =>
        item.mediaType === "video"
          ? loadVideoTexture(item)
          : loader.loadAsync(item.url).catch(() => null)
      )
    )
    if (expectedGeneration !== generation || destroyed) {
      loaded.forEach(releaseTexture)
      return []
    }

    for (const child of [...layer.children]) {
      const item = wanted.get(String(child.userData.item.id))
      if (item) child.userData.item = item
      else {
        if (child === featured) featured = null
        if (child === focusedMoment) {
          const video = videoElement(child.userData.photograph.material.map)
          video?.removeEventListener("ended", finishCinemaFeature)
          video?.removeEventListener("error", finishCinemaFeature)
          clearCinemaTimers()
          focusedMoment = null
          cinemaActive = false
        }
        layer.remove(child)
        disposeObject(child)
      }
    }

    missing.forEach((item, index) => {
      const texture = loaded[index]
      if (!texture) return
      texture.colorSpace = THREE.SRGBColorSpace
      const child = create(item, texture, nextFreeSlot(layer))
      layer.add(child)
      animateNew?.(child)
    })
    return missing
  }

  async function renderContent(next) {
    context = next
    setPresentation(next)
    const current = ++generation
    const regularMoments = (cinema ? next.cinemaMoments || [] : next.moments || []).slice(0, MOMENT_LIMIT)
    const moments = cinema
      ? [...new Map([...regularMoments, ...(next.featuredMoments || [])].map(item => [String(item.id), item])).values()]
      : regularMoments
    const artworks = next.artworks.slice(0, ARTWORK_LIMIT)
    const momentPromise = reconcileLayer(momentLayer, moments, (item, texture, slot) => createMomentCard(item, texture, slot, focus, cinema), card => {
      if (!firstRender) {
        card.userData.arrival = 0
        card.userData.entranceMix = 1
        track(gsap.to(card.userData, {arrival: 1, duration: 1.1, ease: "power2.out"}))
        track(gsap.to(card.userData, {entranceMix: 0, duration: 4.2, delay: 1.8, ease: "power3.inOut"}))
      }
    }, current)
    const artworkPromise = reconcileLayer(artworkLayer, artworks, (item, texture, slot) => createArtwork(item, texture, slot, focus), artwork => {
      if (!firstRender) {
        artwork.userData.arrival = 0
        track(gsap.to(artwork.userData, {arrival: 1, duration: 2.8, ease: "elastic.out(1, 0.55)"}))
      }
    }, current)
    const [, newArtworks] = await Promise.all([momentPromise, artworkPromise])
    if (current !== generation || destroyed) return
    if (featured) {
      const creditVisible = setCreditContent(featured)
      if (focus && creditVisible) gsap.set(credit, {autoAlpha: 1, y: 0})
    }
    if (!firstRender && newArtworks.length) pendingFeatureId = String(newArtworks[0].id)
    if (firstRender) {
      firstRender = false
      armFeatureClock(true)
      scheduleCinema()
    } else if (!featured && artworkLayer.children.length) {
      featureNext(pendingFeatureId)
    }
    if (cinema && !cinemaActive) {
      if (!featureTimer) {
        featureNext()
        armFeatureClock(false)
      }
      if (!cinemaTimer) scheduleCinema()
    }
  }

  function positionMoment(card, elapsed) {
    const data = card.userData
    const slot = data.slot
    const angle = slot * 2.17 + elapsed * 0.105
    const radius = 6.7 + Math.sin(slot * 1.7) * 0.45
    const orbitX = Math.cos(angle) * radius
    const orbitY = ((slot % 9) - 4) * 1.18 + Math.sin(elapsed * 0.22 + data.phase) * 0.2
    const orbitZ = Math.sin(angle) * radius - 2.8
    card.position.set(
      lerp(orbitX, -3.35, data.entranceMix),
      lerp(orbitY, 2.15, data.entranceMix),
      lerp(orbitZ, 3.1, data.entranceMix)
    )
    card.position.lerp(heroPosition, data.heroMix)
    if (cinema) {
      // Derive the orbit orientation from scratch on every frame. Reusing the
      // card's Euler values after a quaternion blend feeds the prior focus
      // rotation back into the orbit and causes flips and visible jitter.
      momentOrbitEuler.set(
        0,
        lerp(-angle + Math.PI / 2, 0, data.entranceMix),
        lerp(Math.sin(slot * 2.1) * 0.055, -0.035, data.entranceMix)
      )
      momentOrbitQuaternion.setFromEuler(momentOrbitEuler)
      card.quaternion.copy(momentOrbitQuaternion).slerp(camera.quaternion, data.heroMix)
    } else {
      card.rotation.y = lerp(-angle + Math.PI / 2, 0, data.entranceMix)
      card.rotation.z = lerp(Math.sin(slot * 2.1) * 0.055, -0.035, data.entranceMix)
    }
    const orbitScale = lerp(1, 1.18, data.entranceMix)
    const heroScale = focusedMediaScale(data.aspect, 1.42)
    card.scale.setScalar(data.arrival * lerp(orbitScale, heroScale, data.heroMix))
    const depth = clamp((card.position.z + 9) / 13, 0.18, 1) * data.arrival
    data.photograph.material.opacity = data.focus
      ? lerp(lerp(0.5 + depth * 0.5, 1, data.entranceMix), 1, data.heroMix) * data.arrival
      : lerp(0.18 + depth * 0.48, 0.92, data.entranceMix) * data.arrival
    if (data.backing) {
      data.backing.material.opacity = lerp(0.08 + depth * 0.24, 0.52, data.entranceMix) * data.arrival
    }
    const isProminent = data.entranceMix > 0.01 || data.heroMix > 0.05
    card.renderOrder = data.heroMix > 0.05 ? 100 : isProminent ? 10 : 0
    if (data.backing) data.backing.renderOrder = data.heroMix > 0.05 ? 100 : isProminent ? 10 : 0
    data.photograph.renderOrder = data.heroMix > 0.05 ? 101 : isProminent ? 11 : 0
    if (data.backing) data.backing.material.depthTest = !isProminent
    data.photograph.material.depthTest = !isProminent
  }

  function positionArtwork(artwork, elapsed) {
    const data = artwork.userData
    const slot = data.slot
    const angle = slot * 2.399 - elapsed * 0.145
    const radius = 4.35 + Math.sin(slot * 1.31) * 0.38
    const baseX = Math.cos(angle) * radius
    const baseY = ((slot % 7) - 3) * 1.05 + Math.sin(elapsed * 0.4 + data.phase) * 0.16
    const baseZ = Math.sin(angle) * radius - 1.25
    artwork.position.set(lerp(baseX, heroPosition.x, data.heroMix), lerp(baseY, heroPosition.y, data.heroMix), lerp(baseZ, heroPosition.z, data.heroMix))
    artwork.quaternion.copy(camera.quaternion)
    const heroScale = data.focus ? focusedMediaScale(data.aspect, 1.9) : 1.58
    artwork.scale.setScalar(data.arrival * lerp(0.82, heroScale, data.heroMix))
    data.halo.material.opacity = data.focus ? 0 : lerp(0.05, 0.3, data.heroMix) * data.arrival
    data.image.material.opacity = data.arrival
    const isFeatured = data.heroMix > 0.05
    artwork.renderOrder = isFeatured ? 100 : 2
    data.halo.renderOrder = isFeatured ? 100 : 1
    data.image.renderOrder = isFeatured ? 101 : 2
    data.halo.material.depthTest = !isFeatured
    data.image.material.depthTest = !isFeatured
  }

  function focusedMediaScale(aspect, mediaHeight) {
    const distance = 8
    const visibleHeight = 2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) * distance
    const visibleWidth = visibleHeight * camera.aspect
    return clamp(Math.min((visibleWidth * 0.9) / (mediaHeight * aspect), (visibleHeight * 0.84) / mediaHeight), 1.65, 5.8)
  }

  function resize(width, height) {
    renderer.setSize(width, height, false)
    camera.aspect = Math.max(0.1, width / Math.max(1, height))
    camera.fov = width < height ? 55 : 43
    camera.updateProjectionMatrix()
  }

  function renderFrame() {
    elapsed += Math.min(clock.getDelta(), 0.05)
    camera.position.set(Math.sin(elapsed * 0.075) * 1.15, Math.sin(elapsed * 0.043) * 0.75, 12.2 + Math.cos(elapsed * 0.061) * 0.7)
    cameraTarget.set(Math.sin(elapsed * 0.05) * 0.3, Math.sin(elapsed * 0.035) * 0.35, -0.4)
    camera.lookAt(cameraTarget)
    if (focus) {
      camera.getWorldDirection(heroPosition)
      heroPosition.multiplyScalar(8).add(camera.position)
    }
    momentLayer.children.forEach(card => positionMoment(card, elapsed))
    artworkLayer.children.forEach(artwork => positionArtwork(artwork, elapsed))
    atmosphere.rotation.y = elapsed * 0.012
    atmosphere.rotation.z = Math.sin(elapsed * 0.03) * 0.08
    renderer.render(scene, camera)
  }

  function pausePresentation() {
    if (presentationPaused || destroyed) return
    presentationPaused = true
    if (featureTimer) window.clearInterval(featureTimer)
    featureTimer = null
    clearCinemaTimers()
    if (focusedMoment) videoElement(focusedMoment.userData.photograph.material.map)?.pause()
    tweens.forEach(animation => animation.pause())
    renderer.setAnimationLoop(null)
    clock.stop()
  }

  function resumePresentation() {
    if (!presentationPaused || destroyed) return
    presentationPaused = false
    tweens.forEach(animation => animation.resume())
    clock.start()
    renderer.setAnimationLoop(renderFrame)
    if (cinemaActive && focusedMoment?.userData.heroMix > 0.98) {
      const video = videoElement(focusedMoment.userData.photograph.material.map)
      if (video) video.play().catch(finishCinemaFeature)
      else cinemaFinishTimer = window.setTimeout(finishCinemaFeature, CINEMA_PHOTO_DURATION_MS)
    } else if (!cinemaActive) {
      armFeatureClock(false)
      scheduleCinema()
    }
  }

  const stopResize = observeSize(container, resize)
  document.addEventListener("visibilitychange", onVisibilityChange)
  await renderContent(initial)
  renderer.setAnimationLoop(renderFrame)

  return {
    update: renderContent,
    resize,
    pausePresentation,
    resumePresentation,
    destroy() {
      destroyed = true
      generation++
      if (featureTimer) window.clearInterval(featureTimer)
      clearCinemaTimers()
      if (focusedMoment) {
        const video = videoElement(focusedMoment.userData.photograph.material.map)
        video?.removeEventListener("ended", finishCinemaFeature)
        video?.removeEventListener("error", finishCinemaFeature)
      }
      document.removeEventListener("visibilitychange", onVisibilityChange)
      tweens.forEach(animation => animation.kill())
      tweens.clear()
      stopResize()
      renderer.setAnimationLoop(null)
      for (const layer of [momentLayer, artworkLayer]) {
        for (const child of [...layer.children]) {
          layer.remove(child)
          disposeObject(child)
        }
      }
      disposeObject(atmosphere)
      renderer.dispose()
      renderer.domElement.remove()
      overlay.remove()
      container.classList.remove("living-spiral")
      container.classList.remove("living-spiral--focus")
    },
  }
}

export async function mount(container, initial) {
  return mountWithOptions(container, initial)
}
