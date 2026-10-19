export function image(item, className = "") {
  const img = document.createElement("img")
  img.src = item.url
  img.alt = item.title || "Workshop contribution"
  img.className = className
  img.decoding = "async"
  return img
}

export function label(item) {
  if (!item.showAttribution || !item.creatorName) return null
  const el = document.createElement("div")
  el.className = "wc-art-credit"
  el.textContent = `Created by ${item.creatorName}`
  return el
}

export function observeSize(container, callback) {
  const observer = new ResizeObserver(entries => {
    const rect = entries[0]?.contentRect
    if (rect) callback(rect.width, rect.height)
  })
  observer.observe(container)
  return () => observer.disconnect()
}
