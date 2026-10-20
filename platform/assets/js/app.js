// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/wake_canvas"
import topbar from "../vendor/topbar"

const runtimeImport = new Function("url", "return import(url)")

function supportedCapability(capability) {
  if (capability === "webgl2") return Boolean(document.createElement("canvas").getContext("webgl2"))
  if (capability === "webgl") {
    const canvas = document.createElement("canvas")
    return Boolean(canvas.getContext("webgl2") || canvas.getContext("webgl"))
  }
  return true
}

const ExperienceRenderer = {
  async mounted() {
    this.disposed = false
    this.renderer = null
    this.pendingSnapshot = null
    this.diagnosticClientId = globalThis.crypto?.randomUUID?.() || `display-${Date.now()}-${Math.random().toString(16).slice(2)}`
    this.requestedVariant = this.el.dataset.displayVariant || null
    this.activeVariant = this.requestedVariant
    this.fallbackUsed = false
    this.fallbackReason = null
    this.rendererFps = null

    this.handleEvent("experience:snapshot", snapshot => {
      if (this.renderer?.update) this.renderer.update(snapshot)
      else this.pendingSnapshot = snapshot
    })

    try {
      const capabilities = JSON.parse(this.el.dataset.rendererCapabilities || "[]")
      const unsupported = capabilities.filter(capability => !supportedCapability(capability))
      const fallbackUrl = this.el.dataset.rendererFallbackUrl
      const rendererUrl = unsupported.length > 0 && fallbackUrl ? fallbackUrl : this.el.dataset.rendererUrl
      const module = await runtimeImport(rendererUrl)
      if (this.disposed) return

      const context = JSON.parse(this.el.dataset.rendererContext || "{}")
      if (rendererUrl === fallbackUrl) {
        context.requestedVariant = context.variant
        context.variant = this.el.dataset.rendererFallbackVariant
        context.fallbackReason = `Unsupported capabilities: ${unsupported.join(", ")}`
        this.activeVariant = context.variant
        this.fallbackUsed = true
        this.fallbackReason = context.fallbackReason
      }
      this.renderer = await module.mount(this.el, context)

      if (this.disposed) {
        this.renderer?.destroy?.()
        return
      }

      if (this.pendingSnapshot && this.renderer?.update) {
        this.renderer.update(this.pendingSnapshot)
        this.pendingSnapshot = null
      }
      this.attachRendererDiagnostics()
      this.startRendererDiagnostics()
    } catch (error) {
      console.error("WakeCanvas renderer failed to mount", error)
      this.rendererDiagnosticError = String(error?.message || error).slice(0, 400)
      this.startRendererDiagnostics("error")
      this.el.innerHTML = `<div style="display:grid;place-items:center;min-height:100vh;background:#151515;color:white;font-family:system-ui;padding:2rem;text-align:center"><div><h1>Display unavailable</h1><p>Open WakeCanvas management for diagnostics.</p></div></div>`
    }
  },

  reportRendererDiagnostic(status, extra = {}) {
    this.rendererDiagnosticStatus = status
    if (extra.error !== undefined) this.rendererDiagnosticError = extra.error
    const bounds = this.el.getBoundingClientRect()
    this.pushEvent("renderer:diagnostic", {
      clientId: this.diagnosticClientId,
      status,
      requestedVariant: this.requestedVariant,
      activeVariant: this.activeVariant,
      fallback: this.fallbackUsed,
      fallbackReason: this.fallbackReason,
      width: Math.max(0, Math.round(bounds.width || window.innerWidth || 0)),
      height: Math.max(0, Math.round(bounds.height || window.innerHeight || 0)),
      devicePixelRatio: Math.min(8, Math.max(0.25, Number(window.devicePixelRatio || 1))),
      fps: this.rendererFps,
      visible: document.visibilityState === "visible",
      webgl2: supportedCapability("webgl2"),
      error: status === "error" ? this.rendererDiagnosticError : null,
      ...extra,
    })
  },

  startRendererDiagnostics(status = "running") {
    this.reportRendererDiagnostic(status)
    this.diagnosticInterval = window.setInterval(
      () => this.reportRendererDiagnostic(this.rendererDiagnosticStatus || status),
      15_000,
    )
    this.fpsStartedAt = performance.now()
    this.fpsFrames = 0

    const sampleFrame = now => {
      if (this.disposed) return
      this.fpsFrames += 1
      const elapsed = now - this.fpsStartedAt
      if (elapsed >= 1_000) {
        this.rendererFps = Math.min(240, (this.fpsFrames * 1_000) / elapsed)
        this.fpsStartedAt = now
        this.fpsFrames = 0
      }
      this.diagnosticFrame = requestAnimationFrame(sampleFrame)
    }

    this.diagnosticFrame = requestAnimationFrame(sampleFrame)
    this.onDiagnosticVisibility = () => this.reportRendererDiagnostic("running")
    this.onDiagnosticResize = () => this.reportRendererDiagnostic("running")
    document.addEventListener("visibilitychange", this.onDiagnosticVisibility)
    window.addEventListener("resize", this.onDiagnosticResize)
  },

  attachRendererDiagnostics() {
    this.rendererCanvas = this.el.querySelector("canvas")
    if (!this.rendererCanvas) return

    this.onRendererContextLost = () => this.reportRendererDiagnostic("context_lost")
    this.onRendererContextRestored = () => this.reportRendererDiagnostic("context_restored")
    this.rendererCanvas.addEventListener("webglcontextlost", this.onRendererContextLost)
    this.rendererCanvas.addEventListener("webglcontextrestored", this.onRendererContextRestored)
  },

  stopRendererDiagnostics() {
    if (this.diagnosticInterval) window.clearInterval(this.diagnosticInterval)
    if (this.diagnosticFrame) cancelAnimationFrame(this.diagnosticFrame)
    document.removeEventListener("visibilitychange", this.onDiagnosticVisibility)
    window.removeEventListener("resize", this.onDiagnosticResize)
    this.rendererCanvas?.removeEventListener("webglcontextlost", this.onRendererContextLost)
    this.rendererCanvas?.removeEventListener("webglcontextrestored", this.onRendererContextRestored)
  },

  destroyed() {
    this.reportRendererDiagnostic("stopped")
    this.disposed = true
    this.stopRendererDiagnostics()
    this.renderer?.destroy?.()
    this.renderer = null
  },
}

const ExperienceMediaInput = {
  mounted() {
    this.source = this.el.querySelector("[data-media-source]")
    this.preview = this.el.querySelector("[data-media-preview]")
    this.status = this.el.querySelector("[data-media-status]")
    this.removeBackground = this.el.querySelector("[data-remove-background]")
    this.tolerance = this.el.querySelector("[data-chroma-tolerance]")
    this.objectUrl = null
    this.sourceFile = null
    this.processingGeneration = 0
    this.toleranceTimer = null
    this.prepare = async () => {
      const file = this.sourceFile
      if (!file) return
      const generation = ++this.processingGeneration
      this.status.textContent = "Preparing image on this device…"
      this.source.disabled = true
      try {
        const module = await runtimeImport(this.el.dataset.processorUrl)
        const removeBackground = this.removeBackground?.checked ?? false
        const tolerance = Number(this.tolerance?.value || 25)
        const prepared = await module.processImage(file, {
          workerUrl: this.el.dataset.workerUrl,
          maxDimension: 2048,
          removeBackground,
          chroma: {tolerance, dilation: 1, feather: 1, despill: true},
        })
        if (generation !== this.processingGeneration) return
        if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
        this.objectUrl = URL.createObjectURL(prepared)
        this.preview.src = this.objectUrl
        this.preview.hidden = false
        this.upload("image", [prepared])
        this.status.textContent = prepared.wakeCanvasMedia?.backgroundRemoval === "preserved-existing-transparency"
          ? "Image ready. Its existing transparent background was preserved."
          : "Image ready to upload."
      } catch (error) {
        if (generation !== this.processingGeneration) return
        console.error("WakeCanvas image preparation failed", error)
        this.status.textContent = `Could not prepare this image: ${error.message}. Please retake it or choose another image.`
      } finally {
        if (generation === this.processingGeneration) this.source.disabled = false
      }
    }
    this.onChange = event => {
      const file = event.target.files?.[0]
      if (!file) return
      this.sourceFile = file
      if (this.el.dataset.retainOriginal === "true") this.upload("original", [file])
      this.prepare()
    }
    this.onRemoveBackgroundChange = () => this.prepare()
    this.onToleranceInput = () => {
      window.clearTimeout(this.toleranceTimer)
      this.toleranceTimer = window.setTimeout(() => this.prepare(), 180)
    }
    this.source.addEventListener("change", this.onChange)
    this.removeBackground?.addEventListener("change", this.onRemoveBackgroundChange)
    this.tolerance?.addEventListener("input", this.onToleranceInput)
  },

  destroyed() {
    this.processingGeneration++
    this.source?.removeEventListener("change", this.onChange)
    this.removeBackground?.removeEventListener("change", this.onRemoveBackgroundChange)
    this.tolerance?.removeEventListener("input", this.onToleranceInput)
    window.clearTimeout(this.toleranceTimer)
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ExperienceRenderer, ExperienceMediaInput},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
