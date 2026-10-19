export function createAudioLevelInput(container, onStatus = () => {}) {
  const button = document.createElement("button")
  button.type = "button"
  button.textContent = "Enable sound response"
  button.setAttribute("aria-label", "Enable microphone sound response")
  Object.assign(button.style, {
    position: "absolute",
    right: "1.25rem",
    bottom: "1.25rem",
    zIndex: "20",
    padding: "0.7rem 1rem",
    border: "1px solid rgba(255,255,255,.45)",
    borderRadius: "999px",
    background: "rgba(10,18,32,.72)",
    color: "white",
    font: "600 14px system-ui, sans-serif",
    cursor: "pointer",
    backdropFilter: "blur(8px)",
  })
  container.append(button)

  let audioContext = null
  let analyser = null
  let stream = null
  let samples = null
  let smoothedLevel = 0
  let disposed = false

  button.addEventListener("click", async () => {
    if (disposed || stream) return
    button.disabled = true
    button.textContent = "Listening…"

    try {
      if (!navigator.mediaDevices?.getUserMedia) throw new Error("Microphone is unavailable")
      stream = await navigator.mediaDevices.getUserMedia({audio: true, video: false})
      if (disposed) {
        stream.getTracks().forEach(track => track.stop())
        return
      }

      const AudioContext = window.AudioContext || window.webkitAudioContext
      if (!AudioContext) throw new Error("Web Audio is unavailable")
      audioContext = new AudioContext()
      await audioContext.resume()
      analyser = audioContext.createAnalyser()
      analyser.fftSize = 512
      analyser.smoothingTimeConstant = 0.82
      samples = new Uint8Array(analyser.fftSize)
      audioContext.createMediaStreamSource(stream).connect(analyser)
      button.textContent = "Sound response on"
      onStatus("active")
      window.setTimeout(() => { if (!disposed) button.style.opacity = "0.45" }, 1600)
    } catch (error) {
      console.warn("WakeCanvas microphone input was not enabled", error)
      stream?.getTracks().forEach(track => track.stop())
      stream = null
      button.disabled = false
      button.textContent = "Sound unavailable — retry"
      onStatus("unavailable")
    }
  })

  return {
    level() {
      if (!analyser || !samples) return 0
      analyser.getByteTimeDomainData(samples)
      let energy = 0
      for (const sample of samples) {
        const normalized = (sample - 128) / 128
        energy += normalized * normalized
      }
      const rms = Math.sqrt(energy / samples.length)
      const measured = Math.min(1, Math.max(0, (rms - 0.008) * 7.5))
      smoothedLevel += (measured - smoothedLevel) * (measured > smoothedLevel ? 0.32 : 0.08)
      return smoothedLevel
    },

    destroy() {
      disposed = true
      stream?.getTracks().forEach(track => track.stop())
      audioContext?.close().catch(() => {})
      button.remove()
      stream = null
      analyser = null
      samples = null
    },
  }
}
