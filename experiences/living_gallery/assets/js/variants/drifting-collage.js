import {Application, Assets, BlurFilter, Container, Sprite} from "pixi.js"
import {observeSize} from "./dom.js"

export async function mount(container, initial) {
  container.replaceChildren()
  const app = new Application()
  await app.init({resizeTo: container, background: "#171612", antialias: true})
  container.appendChild(app.canvas)

  const momentsLayer = new Container()
  const artworkLayer = new Container()
  momentsLayer.filters = [new BlurFilter({strength: 0.7})]
  app.stage.addChild(momentsLayer, artworkLayer)

  let snapshot = initial
  let generation = 0

  async function render(next) {
    snapshot = next
    const current = ++generation
    const all = [...next.moments.slice(0, 8), ...next.artworks.slice(0, 18)]
    const textures = await Promise.all(all.map(item => Assets.load(item.url).catch(() => null)))
    if (current !== generation) return
    momentsLayer.removeChildren()
    artworkLayer.removeChildren()

    next.moments.slice(0, 8).forEach((item, index) => {
      const texture = textures[index]
      if (!texture) return
      const sprite = new Sprite(texture)
      sprite.anchor.set(0.5)
      sprite.alpha = 0.5
      sprite.width = Math.min(app.screen.width * 0.24, 340)
      sprite.height = sprite.width * 0.72
      sprite.x = app.screen.width * (0.12 + (index % 4) * 0.25)
      sprite.y = app.screen.height * (0.2 + (index % 3) * 0.3)
      sprite.rotation = ((index % 5) - 2) * 0.045
      sprite.wcPhase = index * 0.9
      momentsLayer.addChild(sprite)
    })

    next.artworks.slice(0, 18).forEach((item, index) => {
      const texture = textures[next.moments.slice(0, 8).length + index]
      if (!texture) return
      const sprite = new Sprite(texture)
      sprite.anchor.set(0.5)
      sprite.width = Math.min(app.screen.width * (index === 0 ? 0.3 : 0.16), index === 0 ? 520 : 280)
      sprite.height = sprite.width * 0.82
      const angle = index * 2.399
      const radius = index === 0 ? 0 : Math.min(app.screen.width, app.screen.height) * (0.18 + (index % 4) * 0.06)
      sprite.x = app.screen.width / 2 + Math.cos(angle) * radius
      sprite.y = app.screen.height / 2 + Math.sin(angle) * radius
      sprite.wcPhase = index * 0.55
      sprite.wcBaseScaleX = sprite.scale.x
      sprite.wcBaseScaleY = sprite.scale.y
      artworkLayer.addChild(sprite)
    })
  }

  app.ticker.add(ticker => {
    const time = ticker.lastTime / 1000
    momentsLayer.children.forEach((sprite, index) => {
      sprite.y += Math.sin(time * 0.45 + sprite.wcPhase) * 0.08
      sprite.rotation += Math.sin(time * 0.25 + index) * 0.00005
    })
    artworkLayer.children.forEach(sprite => {
      const pulse = 1 + Math.sin(time + sprite.wcPhase) * 0.018
      sprite.scale.set(sprite.wcBaseScaleX * pulse, sprite.wcBaseScaleY * pulse)
    })
  })

  const stopResize = observeSize(container, () => render(snapshot))
  await render(initial)

  return {
    update: render,
    resize: () => render(snapshot),
    destroy() {
      generation++
      stopResize()
      app.destroy(true, {children: true})
      container.replaceChildren()
    },
  }
}
