import {image, label} from "./dom.js"

export async function mount(container, initial) {
  container.replaceChildren()

  function render(snapshot) {
    container.replaceChildren()
    const wall = document.createElement("div")
    wall.className = "tapestry-wall"
    const heading = document.createElement("header")
    heading.innerHTML = `<span>Community Tapestry</span><strong></strong>`
    heading.querySelector("strong").textContent = snapshot.instanceName
    wall.appendChild(heading)

    const grid = document.createElement("div")
    grid.className = "tapestry-grid"
    const items = [...snapshot.artworks, ...snapshot.moments].slice(0, 40)
    items.forEach((item, index) => {
      const figure = document.createElement("figure")
      figure.style.setProperty("--delay", `${index * 45}ms`)
      figure.appendChild(image(item))
      const caption = document.createElement("figcaption")
      caption.textContent = item.title || (index < snapshot.artworks.length ? "Artwork" : "Workshop moment")
      const credit = label(item)
      if (credit) caption.appendChild(credit)
      figure.appendChild(caption)
      grid.appendChild(figure)
    })
    wall.appendChild(grid)

    if (snapshot.messages?.length) {
      const messages = document.createElement("section")
      messages.className = "tapestry-messages"
      snapshot.messages.slice(0, 12).forEach((item, index) => {
        const quote = document.createElement("blockquote")
        quote.style.setProperty("--delay", `${(items.length + index) * 45}ms`)
        const body = document.createElement("p")
        body.textContent = `“${item.body}”`
        quote.appendChild(body)
        if (item.showAttribution && item.authorName) {
          const author = document.createElement("cite")
          author.textContent = `— ${item.authorName}`
          quote.appendChild(author)
        }
        messages.appendChild(quote)
      })
      wall.appendChild(messages)
    }
    container.appendChild(wall)
  }

  render(initial)
  return {update: render, resize() {}, destroy() { container.replaceChildren() }}
}
