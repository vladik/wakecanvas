import type {ChromaOptions} from "./chroma-key"
export type ProcessOptions = {workerUrl: string; maxDimension?: number; removeBackground?: boolean; chroma?: ChromaOptions}
export function processImage(file: File, options: ProcessOptions): Promise<File> {
  return new Promise(async (resolve, reject) => {
    const worker = new Worker(options.workerUrl, {type: "module"}), id = crypto.randomUUID()
    worker.onmessage = event => {
      if (event.data.id !== id) return
      worker.terminate()
      if (!event.data.ok) return reject(new Error(event.data.error))
      const extension = options.removeBackground ? "png" : "webp"
      resolve(new File([event.data.blob], file.name.replace(/\.[^.]+$/, "") + `-prepared.${extension}`, {type: event.data.blob.type}))
    }
    worker.onerror = event => { worker.terminate(); reject(new Error(event.message)) }
    try {
      const buffer = await file.arrayBuffer()
      worker.postMessage({id, buffer, type: file.type, maxDimension: options.maxDimension ?? 2048, removeBackground: options.removeBackground ?? false, chroma: options.chroma ?? {}}, [buffer])
    } catch (error) { worker.terminate(); reject(error) }
  })
}
