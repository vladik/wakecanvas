import {removeConnectedBackground, type ChromaOptions} from "./chroma-key"
type Request = {id: string; buffer: ArrayBuffer; type: string; maxDimension: number; removeBackground: boolean; chroma: ChromaOptions}
self.onmessage = async (event: MessageEvent<Request>) => {
  const request = event.data
  try {
    const bitmap = await createImageBitmap(new Blob([request.buffer], {type: request.type}), {imageOrientation: "from-image"})
    if (bitmap.width * bitmap.height > 32_000_000) throw new Error("Source image exceeds the 32 megapixel limit")
    const scale = Math.min(1, request.maxDimension / Math.max(bitmap.width, bitmap.height))
    const width = Math.max(1, Math.round(bitmap.width * scale)), height = Math.max(1, Math.round(bitmap.height * scale))
    const canvas = new OffscreenCanvas(width, height)
    const context = canvas.getContext("2d", {willReadFrequently: request.removeBackground})
    if (!context) throw new Error("Image processing is unavailable in this browser")
    context.drawImage(bitmap, 0, 0, width, height); bitmap.close()
    if (request.removeBackground) { const image = context.getImageData(0, 0, width, height); removeConnectedBackground(image.data, width, height, request.chroma); context.putImageData(image, 0, 0) }
    const blob = await canvas.convertToBlob({type: request.removeBackground ? "image/png" : "image/webp", quality: 0.9})
    ;(self as DedicatedWorkerGlobalScope).postMessage({id: request.id, ok: true, blob})
  } catch (error) {
    ;(self as DedicatedWorkerGlobalScope).postMessage({id: request.id, ok: false, error: error instanceof Error ? error.message : String(error)})
  }
}
