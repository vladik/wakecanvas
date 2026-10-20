import {image, label} from "./dom.js"

const FEATURE_INTERVAL = 5_000
const LAYOUT_INTERVAL = 7_500
const ARTWORK_LIMIT = 16
const MOMENT_LIMIT = 8
const MESSAGE_LIMIT = 10
const SVG_NS = "http://www.w3.org/2000/svg"
const SLOTS = [
  [13, 28, 18, -5], [35, 21, 16, 3], [58, 27, 19, -2], [82, 20, 15, 5],
  [22, 54, 15, 4], [46, 48, 18, -4], [70, 53, 16, 3], [88, 48, 13, -5],
  [11, 76, 14, 3], [34, 76, 17, -2], [59, 75, 15, 5], [80, 78, 18, -3],
  [7, 45, 11, -6], [95, 67, 11, 6], [48, 88, 12, -2], [65, 10, 12, 3],
  [27, 10, 11, -4], [94, 34, 10, 5], [4, 64, 10, -3], [92, 88, 11, 3],
  [17, 91, 10, -5], [52, 8, 10, 4], [74, 91, 11, -4], [6, 13, 9, 5],
]

const hash = value => [...String(value)].reduce((sum, char) => ((sum * 33) ^ char.charCodeAt(0)) >>> 0, 5381)

function mediaKey(item) { return `${item.kind || "media"}:${item.id}` }

export async function mount(container, initial) {
  container.replaceChildren()
  container.classList.add("community-tapestry")

  const wall = document.createElement("div")
  wall.className = "tapestry-wall"
  wall.innerHTML = `<header><span>Made by many hands</span><strong></strong></header><div class="tapestry-loom" aria-hidden="true"></div>`
  wall.querySelector("header strong").textContent = initial.instanceName || "Community Tapestry"

  const threads = document.createElementNS(SVG_NS, "svg")
  threads.classList.add("tapestry-threads")
  threads.setAttribute("viewBox", "0 0 1000 600")
  threads.setAttribute("preserveAspectRatio", "none")
  const mediaLayer = document.createElement("div")
  mediaLayer.className = "tapestry-media"
  const messageLayer = document.createElement("div")
  messageLayer.className = "tapestry-messages"
  wall.append(threads, mediaLayer, messageLayer)
  container.appendChild(wall)

  const mediaNodes = new Map()
  const messageNodes = new Map()
  let featureTimer = null
  let layoutTimer = null
  let featuredId = null
  let layoutStep = 0

  function makeFigure(item, kind, slotIndex) {
    const [x, y, width, rotation] = SLOTS[slotIndex % SLOTS.length]
    const figure = document.createElement("figure")
    figure.className = `tapestry-piece tapestry-piece--${kind} tapestry-piece--new`
    figure.dataset.key = mediaKey(item)
    figure.style.setProperty("--x", `${x}%`)
    figure.style.setProperty("--y", `${y}%`)
    figure.style.setProperty("--w", `${width}vw`)
    figure.style.setProperty("--r", `${rotation}deg`)
    figure.style.setProperty("--drift-duration", `${8 + (hash(item.id) % 7)}s`)
    figure.style.setProperty("--drift-delay", `${-(hash(item.id) % 8)}s`)
    figure.style.setProperty("--accent", `hsl(${28 + hash(item.id) % 190} 38% 48%)`)
    figure.appendChild(image(item))
    const caption = document.createElement("figcaption")
    const title = document.createElement("strong")
    title.textContent = item.title || (kind === "artwork" ? "Workshop artwork" : "Workshop moment")
    caption.appendChild(title)
    const credit = label(item)
    if (credit) caption.appendChild(credit)
    figure.appendChild(caption)
    window.setTimeout(() => figure.classList.remove("tapestry-piece--new"), 1800)
    return figure
  }

  function updateFigure(figure, item) {
    const img = figure.querySelector("img")
    if (img.src !== new URL(item.url, window.location.href).href) img.src = item.url
    img.alt = item.title || "Workshop contribution"
    figure.querySelector("figcaption strong").textContent = item.title || (item.kind === "artwork" ? "Workshop artwork" : "Workshop moment")
  }

  function makeMessage(item, index) {
    const message = document.createElement("blockquote")
    message.className = "tapestry-message tapestry-message--new"
    message.dataset.id = String(item.id)
    message.style.setProperty("--message-index", index)
    const body = document.createElement("p")
    const author = document.createElement("cite")
    message.append(body, author)
    updateMessage(message, item)
    window.setTimeout(() => message.classList.remove("tapestry-message--new"), 1800)
    return message
  }

  function updateMessage(message, item) {
    message.querySelector("p").textContent = `“${item.body}”`
    const author = message.querySelector("cite")
    author.textContent = item.showAttribution && item.authorName ? `— ${item.authorName}` : ""
    author.hidden = !author.textContent
  }

  function drawThreads(items) {
    threads.replaceChildren()
    const points = items.map((item, index) => {
      const slot = SLOTS[index % SLOTS.length]
      return {x: slot[0] * 10, y: slot[1] * 6, seed: hash(item.id)}
    })
    points.forEach((point, index) => {
      const next = points[(index + 3) % points.length]
      if (!next || next === point) return
      const path = document.createElementNS(SVG_NS, "path")
      const bend = ((point.seed % 120) - 60)
      path.setAttribute("d", `M ${point.x} ${point.y} C ${point.x + bend} ${(point.y + next.y) / 2}, ${next.x - bend} ${(point.y + next.y) / 2}, ${next.x} ${next.y}`)
      path.style.setProperty("--thread", `hsl(${24 + point.seed % 190} 34% 45%)`)
      threads.appendChild(path)
    })
  }

  function featureNext(preferredId) {
    const artworks = [...mediaNodes.values()].filter(node => node.dataset.kind === "artwork")
    if (!artworks.length) return
    const current = artworks.findIndex(node => node.dataset.id === featuredId)
    const next = preferredId
      ? artworks.find(node => node.dataset.id === String(preferredId)) || artworks[(current + 1) % artworks.length]
      : artworks[(current + 1) % artworks.length]
    artworks.forEach(node => node.classList.toggle("tapestry-piece--featured", node === next))
    featuredId = next.dataset.id
  }

  function armFeatureClock() {
    if (featureTimer) window.clearInterval(featureTimer)
    featureTimer = window.setInterval(() => featureNext(), FEATURE_INTERVAL)
  }

  function moveTheWeave() {
    layoutStep++
    const nodes = [...mediaNodes.values()]
    nodes.forEach((node, index) => {
      const slot = SLOTS[(index + layoutStep) % SLOTS.length]
      node.style.setProperty("--x", `${slot[0]}%`)
      node.style.setProperty("--y", `${slot[1]}%`)
      node.style.setProperty("--r", `${slot[3]}deg`)
    })
  }

  function armLayoutClock() {
    if (layoutTimer) window.clearInterval(layoutTimer)
    layoutTimer = window.setInterval(moveTheWeave, LAYOUT_INTERVAL)
  }

  function render(snapshot) {
    const items = [
      ...snapshot.artworks.slice(0, ARTWORK_LIMIT).map(item => ({...item, kind: "artwork"})),
      ...snapshot.moments.slice(0, MOMENT_LIMIT).map(item => ({...item, kind: "moment"})),
    ]
    const wanted = new Set(items.map(mediaKey))
    let newArtworkId = null

    for (const [key, node] of mediaNodes) {
      if (!wanted.has(key)) {
        node.remove()
        mediaNodes.delete(key)
      }
    }
    items.forEach((item, index) => {
      const key = mediaKey(item)
      let node = mediaNodes.get(key)
      if (!node) {
        const usedSlots = new Set([...mediaNodes.values()].map(existing => Number(existing.dataset.slot)))
        let slot = 0
        while (usedSlots.has(slot) && slot < SLOTS.length) slot++
        node = makeFigure(item, item.kind, slot < SLOTS.length ? slot : index)
        node.dataset.id = String(item.id)
        node.dataset.kind = item.kind
        node.dataset.slot = String(slot < SLOTS.length ? slot : index % SLOTS.length)
        mediaNodes.set(key, node)
        mediaLayer.appendChild(node)
        if (item.kind === "artwork") newArtworkId = item.id
      } else {
        updateFigure(node, item)
      }
    })
    drawThreads(items)

    const messages = (snapshot.messages || []).slice(0, MESSAGE_LIMIT)
    const wantedMessages = new Set(messages.map(item => String(item.id)))
    for (const [id, node] of messageNodes) {
      if (!wantedMessages.has(id)) {
        node.remove()
        messageNodes.delete(id)
      }
    }
    messages.forEach((item, index) => {
      const id = String(item.id)
      let node = messageNodes.get(id)
      if (!node) {
        node = makeMessage(item, index)
        messageNodes.set(id, node)
        messageLayer.appendChild(node)
      } else {
        updateMessage(node, item)
      }
    })

    if (newArtworkId || !featuredId || ![...mediaNodes.values()].some(node => node.dataset.id === featuredId)) {
      featureNext(newArtworkId)
    }
  }

  function onVisibilityChange() {
    if (document.hidden) {
      if (featureTimer) window.clearInterval(featureTimer)
      featureTimer = null
      if (layoutTimer) window.clearInterval(layoutTimer)
      layoutTimer = null
    } else {
      armFeatureClock()
      armLayoutClock()
    }
  }

  render(initial)
  armFeatureClock()
  armLayoutClock()
  document.addEventListener("visibilitychange", onVisibilityChange)

  return {
    update: render,
    resize() {},
    destroy() {
      if (featureTimer) window.clearInterval(featureTimer)
      if (layoutTimer) window.clearInterval(layoutTimer)
      document.removeEventListener("visibilitychange", onVisibilityChange)
      container.classList.remove("community-tapestry")
      container.replaceChildren()
    },
  }
}
