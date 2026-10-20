const ARTWORK_INTERVAL = 7_500
const MEMORY_INTERVAL = 5_500

function mediaKey(item) {
  return String(item.id)
}

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("living-light")

  const wall = document.createElement("div")
  wall.className = "spotlight-wall"
  wall.innerHTML = `
    <div class="spotlight-memories" aria-hidden="true">
      <div class="spotlight-memory spotlight-memory--a"><img alt=""></div>
      <div class="spotlight-memory spotlight-memory--b"><img alt=""></div>
    </div>
    <div class="spotlight-lightfield" aria-hidden="true"><i></i><i></i><i></i></div>
    <header><span>Created here, together</span><strong></strong></header>
    <main class="spotlight-stage">
      <img class="spotlight-echo spotlight-echo--left" alt="" aria-hidden="true">
      <img class="spotlight-echo spotlight-echo--right" alt="" aria-hidden="true">
      <div class="spotlight-aperture">
        <div class="spotlight-frame"><img class="spotlight-main" alt=""></div>
      </div>
      <div class="spotlight-caption"><span></span><strong></strong><small></small></div>
    </main>
    <div class="spotlight-waiting">Waiting for the first artwork</div>
    <div class="spotlight-progress" aria-hidden="true"><i></i></div>
  `
  wall.querySelector("header strong").textContent = initial.instanceName || "Living Light"
  container.appendChild(wall)

  const stage = wall.querySelector(".spotlight-stage")
  const waiting = wall.querySelector(".spotlight-waiting")
  const mainImage = wall.querySelector(".spotlight-main")
  const echoes = [...wall.querySelectorAll(".spotlight-echo")]
  const captionKicker = wall.querySelector(".spotlight-caption span")
  const captionTitle = wall.querySelector(".spotlight-caption strong")
  const captionCredit = wall.querySelector(".spotlight-caption small")
  const progress = wall.querySelector(".spotlight-progress i")
  const memoryLayers = [...wall.querySelectorAll(".spotlight-memory")]

  let artworks = []
  let moments = []
  let artworkIndex = -1
  let memoryIndex = -1
  let activeMemoryLayer = 0
  let artworkTimer = null
  let memoryTimer = null
  let transitionTimer = null
  let revealTimer = null
  let destroyed = false
  let transitioning = false
  let queuedArtworkIndex = null

  function applyArtwork(item, index) {
    mainImage.src = item.url
    mainImage.alt = item.title || "Workshop artwork"
    echoes.forEach(image => { image.src = item.url })
    captionKicker.textContent = `Artwork ${index + 1} of ${artworks.length}`
    captionTitle.textContent = item.title || "A workshop creation"
    captionCredit.textContent = item.showAttribution && item.creatorName ? `Created by ${item.creatorName}` : "Created by the workshop community"
    progress.style.animation = "none"
    progress.offsetWidth
    progress.style.animation = "spotlight-progress 7.5s linear both"
  }

  function showArtwork(index, immediate = false) {
    if (!artworks.length) {
      stage.hidden = true
      waiting.hidden = false
      artworkIndex = -1
      return
    }
    const normalized = ((index % artworks.length) + artworks.length) % artworks.length
    if (transitioning && !immediate) {
      queuedArtworkIndex = normalized
      return
    }
    stage.hidden = false
    waiting.hidden = true

    if (immediate || artworkIndex < 0) {
      artworkIndex = normalized
      applyArtwork(artworks[artworkIndex], artworkIndex)
      stage.classList.add("spotlight-stage--revealed")
      return
    }

    transitioning = true
    stage.classList.remove("spotlight-stage--revealed")
    stage.classList.add("spotlight-stage--changing")
    transitionTimer = window.setTimeout(() => {
      if (destroyed) return
      artworkIndex = normalized
      applyArtwork(artworks[artworkIndex], artworkIndex)
      stage.classList.remove("spotlight-stage--changing")
      stage.classList.add("spotlight-stage--revealed")
      revealTimer = window.setTimeout(() => {
        transitioning = false
        if (queuedArtworkIndex !== null) {
          const queued = queuedArtworkIndex
          queuedArtworkIndex = null
          showArtwork(queued)
        }
      }, 850)
    }, 520)
  }

  function showMemory(index, immediate = false) {
    if (!moments.length) {
      memoryLayers.forEach(layer => layer.classList.remove("spotlight-memory--active"))
      memoryIndex = -1
      return
    }
    memoryIndex = ((index % moments.length) + moments.length) % moments.length
    const nextLayer = immediate ? activeMemoryLayer : 1 - activeMemoryLayer
    const layer = memoryLayers[nextLayer]
    const item = moments[memoryIndex]
    const image = layer.querySelector("img")
    image.src = item.url
    image.alt = item.title || "Workshop memory"
    if (immediate) {
      layer.classList.add("spotlight-memory--active")
    } else {
      memoryLayers[activeMemoryLayer].classList.remove("spotlight-memory--active")
      layer.classList.add("spotlight-memory--active")
      activeMemoryLayer = nextLayer
    }
  }

  function armClocks() {
    if (artworkTimer) window.clearInterval(artworkTimer)
    if (memoryTimer) window.clearInterval(memoryTimer)
    artworkTimer = window.setInterval(() => showArtwork(artworkIndex + 1), ARTWORK_INTERVAL)
    memoryTimer = window.setInterval(() => showMemory(memoryIndex + 1), MEMORY_INTERVAL)
  }

  function update(snapshot) {
    const previousArtworkIds = new Set(artworks.map(mediaKey))
    artworks = snapshot.artworks.slice(0, 30)
    moments = snapshot.moments.slice(0, 30)
    const newArtwork = artworks.find(item => !previousArtworkIds.has(mediaKey(item)))

    if (!artworks.length) {
      showArtwork(0, true)
    } else if (newArtwork) {
      showArtwork(artworks.findIndex(item => mediaKey(item) === mediaKey(newArtwork)), artworkIndex < 0)
    } else if (artworkIndex < 0 || artworkIndex >= artworks.length) {
      showArtwork(0, true)
    }

    if (!moments.length) showMemory(0, true)
    else if (memoryIndex < 0 || memoryIndex >= moments.length) showMemory(0, true)
  }

  function onVisibilityChange() {
    if (document.hidden) {
      if (artworkTimer) window.clearInterval(artworkTimer)
      if (memoryTimer) window.clearInterval(memoryTimer)
      artworkTimer = null
      memoryTimer = null
    } else {
      armClocks()
    }
  }

  update(initial)
  armClocks()
  document.addEventListener("visibilitychange", onVisibilityChange)

  return {
    update,
    resize() {},
    destroy() {
      destroyed = true
      if (artworkTimer) window.clearInterval(artworkTimer)
      if (memoryTimer) window.clearInterval(memoryTimer)
      if (transitionTimer) window.clearTimeout(transitionTimer)
      if (revealTimer) window.clearTimeout(revealTimer)
      document.removeEventListener("visibilitychange", onVisibilityChange)
      container.classList.remove("living-light")
      container.replaceChildren()
    },
  }
}
