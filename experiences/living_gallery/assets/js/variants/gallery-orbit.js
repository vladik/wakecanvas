import * as THREE from "three"
import {observeSize} from "./dom.js"

export async function mount(container, initial) {
  container.replaceChildren()
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false})
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
  renderer.setClearColor(0x0c1114)
  container.appendChild(renderer.domElement)

  const scene = new THREE.Scene()
  scene.fog = new THREE.FogExp2(0x0c1114, 0.055)
  const camera = new THREE.PerspectiveCamera(48, 1, 0.1, 100)
  camera.position.set(0, 0.5, 9)
  scene.add(new THREE.AmbientLight(0xffffff, 1.7))
  const key = new THREE.DirectionalLight(0xffd9ae, 2.6)
  key.position.set(4, 6, 5)
  scene.add(key)

  const group = new THREE.Group()
  scene.add(group)
  const loader = new THREE.TextureLoader()
  let frame = 0
  let snapshot = initial
  let generation = 0

  function clear() {
    for (const child of [...group.children]) {
      group.remove(child)
      child.geometry?.dispose()
      child.material?.map?.dispose()
      child.material?.dispose()
    }
  }

  async function renderContent(next) {
    snapshot = next
    const current = ++generation
    const items = [...next.artworks.slice(0, 16), ...next.moments.slice(0, 8)]
    const textures = await Promise.all(items.map(item => loader.loadAsync(item.url).catch(() => null)))
    if (current !== generation) {
      textures.forEach(texture => texture?.dispose())
      return
    }
    clear()
    textures.forEach((texture, index) => {
      if (!texture) return
      texture.colorSpace = THREE.SRGBColorSpace
      const isArtwork = index < next.artworks.slice(0, 16).length
      const geometry = new THREE.PlaneGeometry(isArtwork ? 2.1 : 2.8, isArtwork ? 1.7 : 1.9)
      const material = new THREE.MeshStandardMaterial({map: texture, transparent: true, opacity: isArtwork ? 1 : 0.48, side: THREE.DoubleSide})
      const mesh = new THREE.Mesh(geometry, material)
      const angle = index * 2.399
      const radius = isArtwork ? 3.2 + (index % 3) * 0.8 : 6.2
      mesh.position.set(Math.cos(angle) * radius, ((index % 5) - 2) * 0.85, Math.sin(angle) * radius - 2)
      mesh.lookAt(camera.position)
      mesh.userData.phase = index * 0.7
      group.add(mesh)
    })
  }

  function resize(width, height) {
    renderer.setSize(width, height, false)
    camera.aspect = Math.max(0.1, width / Math.max(1, height))
    camera.updateProjectionMatrix()
  }

  const stopResize = observeSize(container, resize)
  await renderContent(initial)

  renderer.setAnimationLoop(time => {
    group.rotation.y = time * 0.000055
    group.children.forEach(mesh => { mesh.position.y += Math.sin(time * 0.0007 + mesh.userData.phase) * 0.0008 })
    renderer.render(scene, camera)
  })

  return {
    update: renderContent,
    resize,
    destroy() {
      generation++
      stopResize()
      renderer.setAnimationLoop(null)
      clear()
      renderer.dispose()
      renderer.domElement.remove()
    },
  }
}
