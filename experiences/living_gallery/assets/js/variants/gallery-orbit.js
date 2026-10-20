import {gsap} from "gsap"
import * as THREE from "three"
import {observeSize} from "./dom.js"

const TAU = Math.PI * 2
const ARTWORK_LIMIT = 28
const MOMENT_LIMIT = 16
const FEATURE_INTERVAL = 10

const clamp = (value, min, max) => Math.max(min, Math.min(max, value))
const lerp = (from, to, amount) => from + (to - from) * amount

function textureAspect(texture) {
  const image = texture?.image
  return image?.width && image?.height ? image.width / image.height : 4 / 3
}

function disposeObject(object) {
  object.traverse(child => {
    child.geometry?.dispose()
    if (Array.isArray(child.material)) {
      child.material.forEach(material => {
        material.map?.dispose()
        material.dispose()
      })
    } else {
      child.material?.map?.dispose()
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

function createMomentCard(item, texture, slot) {
  const aspect = clamp(textureAspect(texture), 0.72, 1.65)
  const height = 1.42
  const width = height * aspect
  const card = new THREE.Group()
  const backing = new THREE.Mesh(
    new THREE.PlaneGeometry(width + 0.16, height + 0.16),
    new THREE.MeshStandardMaterial({color: 0xe7dbc7, transparent: true, opacity: 0.3, roughness: 0.48, metalness: 0.12, side: THREE.DoubleSide})
  )
  backing.position.z = -0.025
  const photograph = new THREE.Mesh(
    new THREE.PlaneGeometry(width, height),
    new THREE.MeshBasicMaterial({map: texture, color: 0xb9c1c3, transparent: true, opacity: 0.58, side: THREE.DoubleSide})
  )
  card.add(backing, photograph)
  card.userData = {item, slot, kind: "moment", photograph, backing, phase: slot * 0.71, arrival: 1, entranceMix: 0}
  return card
}

function createArtwork(item, texture, slot) {
  const aspect = clamp(textureAspect(texture), 0.58, 1.8)
  const height = 1.9
  const width = height * aspect
  const artwork = new THREE.Group()
  const halo = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 1.13, height * 1.13),
    new THREE.MeshBasicMaterial({color: 0xffd49a, transparent: true, opacity: 0.1, blending: THREE.AdditiveBlending, depthWrite: false})
  )
  halo.position.z = -0.045
  const image = new THREE.Mesh(
    new THREE.PlaneGeometry(width, height),
    new THREE.MeshBasicMaterial({map: texture, transparent: true, opacity: 1, side: THREE.DoubleSide, depthWrite: false})
  )
  artwork.add(halo, image)
  artwork.userData = {item, slot, kind: "artwork", image, halo, heroMix: 0, arrival: 1, phase: slot * 0.83}
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

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("living-spiral")
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false, powerPreference: "high-performance"})
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75))
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 0.92
  renderer.setClearColor(0x050609)
  container.appendChild(renderer.domElement)

  const overlay = document.createElement("div")
  overlay.className = "living-spiral__overlay"
  overlay.innerHTML = `<div class="living-spiral__identity"><span>Living Gallery</span><strong></strong></div><div class="living-spiral__credit" aria-live="polite"><span>Now in the light</span><strong></strong></div><div class="living-spiral__vignette"></div><div class="living-spiral__grain"></div>`
  container.appendChild(overlay)
  overlay.querySelector(".living-spiral__identity strong").textContent = initial.instanceName || "Workshop Moments"
  const credit = overlay.querySelector(".living-spiral__credit")
  const creditName = credit.querySelector("strong")

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
  const tweens = new Set()
  let elapsed = 0
  let generation = 0
  let featureTimer = null
  let featured = null
  let pendingFeatureId = null
  let destroyed = false
  let firstRender = true

  function track(animation, onComplete) {
    tweens.add(animation)
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

  function showCredit(artwork) {
    const item = artwork.userData.item
    creditName.textContent = item.showAttribution && item.creatorName ? `Created by ${item.creatorName}` : item.title || "A new creation"
    gsap.set(credit, {autoAlpha: 0, y: 16})
    track(gsap.to(credit, {autoAlpha: 1, y: 0, duration: 1, delay: 0.35, ease: "power3.out"}))
  }

  function activateFeature(next) {
    if (!next || destroyed) return
    featured = next
    showCredit(next)
    track(gsap.to(next.userData, {heroMix: 1, duration: 2.1, ease: "power3.inOut"}))
  }

  function featureNext(preferredId) {
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
    if (immediate) featureNext(pendingFeatureId)
    featureTimer = window.setInterval(() => featureNext(pendingFeatureId), FEATURE_INTERVAL * 1000)
  }

  function onVisibilityChange() {
    if (document.hidden) {
      if (featureTimer) window.clearInterval(featureTimer)
      featureTimer = null
      tweens.forEach(animation => animation.pause())
    } else {
      tweens.forEach(animation => animation.resume())
      armFeatureClock(false)
    }
  }

  async function reconcileLayer(layer, items, create, animateNew, expectedGeneration) {
    const wanted = new Map(items.map(item => [String(item.id), item]))
    const existing = new Map(layer.children.map(child => [String(child.userData.item.id), child]))
    const missing = items.filter(item => !existing.has(String(item.id)))
    const loaded = await Promise.all(missing.map(item => loader.loadAsync(item.url).catch(() => null)))
    if (expectedGeneration !== generation || destroyed) {
      loaded.forEach(texture => texture?.dispose())
      return []
    }

    for (const child of [...layer.children]) {
      const item = wanted.get(String(child.userData.item.id))
      if (item) child.userData.item = item
      else {
        if (child === featured) featured = null
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
    const current = ++generation
    const moments = next.moments.slice(0, MOMENT_LIMIT)
    const artworks = next.artworks.slice(0, ARTWORK_LIMIT)
    const momentPromise = reconcileLayer(momentLayer, moments, createMomentCard, card => {
      if (!firstRender) {
        card.userData.arrival = 0
        card.userData.entranceMix = 1
        track(gsap.to(card.userData, {arrival: 1, duration: 1.1, ease: "power2.out"}))
        track(gsap.to(card.userData, {entranceMix: 0, duration: 4.2, delay: 1.8, ease: "power3.inOut"}))
      }
    }, current)
    const artworkPromise = reconcileLayer(artworkLayer, artworks, createArtwork, artwork => {
      if (!firstRender) {
        artwork.userData.arrival = 0
        track(gsap.to(artwork.userData, {arrival: 1, duration: 2.8, ease: "elastic.out(1, 0.55)"}))
      }
    }, current)
    const [, newArtworks] = await Promise.all([momentPromise, artworkPromise])
    if (current !== generation || destroyed) return
    if (!firstRender && newArtworks.length) pendingFeatureId = String(newArtworks[0].id)
    if (firstRender) {
      firstRender = false
      armFeatureClock(true)
    } else if (!featured && artworkLayer.children.length) {
      featureNext(pendingFeatureId)
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
    card.rotation.y = lerp(-angle + Math.PI / 2, 0, data.entranceMix)
    card.rotation.z = lerp(Math.sin(slot * 2.1) * 0.055, -0.035, data.entranceMix)
    card.scale.setScalar(data.arrival * lerp(1, 1.18, data.entranceMix))
    const depth = clamp((card.position.z + 9) / 13, 0.18, 1) * data.arrival
    data.photograph.material.opacity = lerp(0.18 + depth * 0.48, 0.92, data.entranceMix) * data.arrival
    data.backing.material.opacity = lerp(0.08 + depth * 0.24, 0.52, data.entranceMix) * data.arrival
    const isEntering = data.entranceMix > 0.01
    card.renderOrder = isEntering ? 10 : 0
    data.backing.renderOrder = isEntering ? 10 : 0
    data.photograph.renderOrder = isEntering ? 11 : 0
    data.backing.material.depthTest = !isEntering
    data.photograph.material.depthTest = !isEntering
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
    artwork.scale.setScalar(data.arrival * lerp(0.82, 1.58, data.heroMix))
    data.halo.material.opacity = lerp(0.05, 0.3, data.heroMix) * data.arrival
    data.image.material.opacity = data.arrival
    const isFeatured = data.heroMix > 0.05
    artwork.renderOrder = isFeatured ? 100 : 2
    data.halo.renderOrder = isFeatured ? 100 : 1
    data.image.renderOrder = isFeatured ? 101 : 2
    data.halo.material.depthTest = !isFeatured
    data.image.material.depthTest = !isFeatured
  }

  function resize(width, height) {
    renderer.setSize(width, height, false)
    camera.aspect = Math.max(0.1, width / Math.max(1, height))
    camera.fov = width < height ? 55 : 43
    camera.updateProjectionMatrix()
  }

  const stopResize = observeSize(container, resize)
  document.addEventListener("visibilitychange", onVisibilityChange)
  await renderContent(initial)
  renderer.setAnimationLoop(() => {
    elapsed += Math.min(clock.getDelta(), 0.05)
    momentLayer.children.forEach(card => positionMoment(card, elapsed))
    artworkLayer.children.forEach(artwork => positionArtwork(artwork, elapsed))
    camera.position.set(Math.sin(elapsed * 0.075) * 1.15, Math.sin(elapsed * 0.043) * 0.75, 12.2 + Math.cos(elapsed * 0.061) * 0.7)
    cameraTarget.set(Math.sin(elapsed * 0.05) * 0.3, Math.sin(elapsed * 0.035) * 0.35, -0.4)
    camera.lookAt(cameraTarget)
    atmosphere.rotation.y = elapsed * 0.012
    atmosphere.rotation.z = Math.sin(elapsed * 0.03) * 0.08
    renderer.render(scene, camera)
  })

  return {
    update: renderContent,
    resize,
    destroy() {
      destroyed = true
      generation++
      if (featureTimer) window.clearInterval(featureTimer)
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
    },
  }
}
