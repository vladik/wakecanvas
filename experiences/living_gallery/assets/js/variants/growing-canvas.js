import p5 from "p5"
import {createAudioLevelInput} from "./audio-level-input.js"

export async function mount(container, initial) {
  container.replaceChildren()
  container.style.position = "relative"
  let snapshot = initial
  const audio = createAudioLevelInput(container)

  const sketch = new p5(p => {
    const seeds = () => snapshot.artworks.length ? snapshot.artworks : [{id: "waiting"}]

    p.setup = () => {
      p.createCanvas(container.clientWidth, container.clientHeight)
      p.colorMode(p.HSB, 360, 100, 100, 100)
      p.noiseDetail(3, 0.55)
    }

    p.windowResized = () => p.resizeCanvas(container.clientWidth, container.clientHeight)

    p.draw = () => {
      const sound = audio.level()
      p.background(214, 28, 10, 16)
      p.blendMode(p.ADD)
      seeds().slice(0, 35).forEach((item, index) => {
        const seed = [...String(item.id)].reduce((sum, char) => sum + char.charCodeAt(0), 0)
        const baseX = p.noise(seed * 0.01) * p.width
        const hue = (seed * 7 + p.frameCount * (0.08 + sound * 0.45)) % 360
        p.noFill()
        p.stroke(hue, 55, 92, 24)
        p.strokeWeight(1.5 + (index % 4) * 0.45 + sound * 2.5)
        p.beginShape()
        for (let y = p.height + 30; y > -30; y -= 14) {
          const sway = Math.sin(y * 0.018 + p.frameCount * (0.012 + sound * 0.025) + seed) *
            (24 + index * 0.7 + sound * 58)
          p.splineVertex(baseX + sway, y)
        }
        p.endShape()
      })
      p.blendMode(p.BLEND)
      p.noStroke()
      p.fill(45, 18, 98, 75)
      p.textAlign(p.CENTER)
      p.textSize(Math.max(18, p.width * 0.025))
      p.text(snapshot.instanceName, p.width / 2, 48)
    }
  }, container)

  return {
    update(next) { snapshot = next },
    resize() { sketch.resizeCanvas(container.clientWidth, container.clientHeight) },
    destroy() { audio.destroy(); sketch.remove(); container.replaceChildren() },
  }
}
