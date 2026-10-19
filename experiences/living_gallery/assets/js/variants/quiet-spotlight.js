import {image, label} from "./dom.js"

export async function mount(container, initial) {
  container.replaceChildren()

  function render(snapshot) {
    container.replaceChildren()
    const wall = document.createElement("div")
    wall.className = "spotlight-wall"
    const heading = document.createElement("header")
    heading.textContent = snapshot.instanceName
    wall.appendChild(heading)
    snapshot.moments.slice(0, 4).forEach(item => {
      const moment = image(item, "spotlight-moment")
      wall.appendChild(moment)
    })
    const artwork = snapshot.artworks[0]
    if (artwork) {
      const frame = document.createElement("div")
      frame.className = "spotlight-artwork"
      frame.appendChild(image(artwork))
      wall.appendChild(frame)
      const credit = label(artwork)
      if (credit) wall.appendChild(credit)
    } else {
      const waiting = document.createElement("div")
      waiting.className = "spotlight-waiting"
      waiting.textContent = "Waiting for the first artwork"
      wall.appendChild(waiting)
    }
    container.appendChild(wall)
  }

  render(initial)
  return {update: render, resize() {}, destroy() { container.replaceChildren() }}
}
