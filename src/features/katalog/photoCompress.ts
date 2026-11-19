import {
  MAX_BYTES,
  dimensionsFor,
  firstStep,
  isAcceptable,
  isWithinLimit,
  nextStep,
} from './photoPlan'
import type { Result } from './types'

export interface CompressedPhoto {
  blob: Blob
  mime: 'image/webp' | 'image/jpeg'
}

interface Decoded {
  source: CanvasImageSource
  width: number
  height: number
  release: () => void
}

async function decode(file: Blob): Promise<Decoded> {
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
      return { source: bitmap, width: bitmap.width, height: bitmap.height, release: () => bitmap.close() }
    } catch {
      /* lanjut ke jalur Image */
    }
  }
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.src = url
    await img.decode()
    return { source: img, width: img.naturalWidth, height: img.naturalHeight, release: () => undefined }
  } finally {
    URL.revokeObjectURL(url)
  }
}

function encode(canvas: HTMLCanvasElement, mime: string, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, mime, quality))
}

// Kompres di perangkat: sisi terpanjang 1600 px, JPEG atau WebP, target sekitar 200 KB (FR-013).
// Bagian kanvas ini diuji manual; hitungannya ada di photoPlan.ts.
export async function compressImage(file: File): Promise<Result<CompressedPhoto>> {
  let decoded: Decoded
  try {
    decoded = await decode(file)
  } catch {
    return { ok: false, error: { code: 'PHOTO_UNREADABLE', message: 'Berkas ini bukan gambar yang dapat dibaca.' } }
  }

  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  if (!ctx) {
    decoded.release()
    return { ok: false, error: { code: 'PHOTO_NO_CANVAS', message: 'Perangkat tidak dapat memproses gambar.' } }
  }

  let mime: 'image/webp' | 'image/jpeg' = 'image/webp'
  let best: CompressedPhoto | null = null
  try {
    for (let step = firstStep(); ; ) {
      const { width, height } = dimensionsFor(decoded.width, decoded.height, step.scale)
      canvas.width = width
      canvas.height = height
      // Latar putih agar piksel transparan tidak menjadi hitam pada JPEG.
      ctx.fillStyle = '#ffffff'
      ctx.fillRect(0, 0, width, height)
      ctx.drawImage(decoded.source, 0, 0, width, height)

      let blob = await encode(canvas, mime, step.quality)
      // Browser yang tidak bisa menyandikan WebP mengembalikan PNG; beralih ke JPEG.
      if (blob && mime === 'image/webp' && blob.type !== 'image/webp') {
        mime = 'image/jpeg'
        blob = await encode(canvas, mime, step.quality)
      }
      if (!blob) {
        return { ok: false, error: { code: 'PHOTO_ENCODE', message: 'Foto gagal diproses.' } }
      }
      if (!best || blob.size < best.blob.size) best = { blob, mime }
      if (isAcceptable(blob.size)) break
      const next = nextStep(step)
      if (!next) break
      step = next
    }
  } finally {
    decoded.release()
    canvas.width = 0
    canvas.height = 0
  }

  if (!best || !isWithinLimit(best.blob.size)) {
    return {
      ok: false,
      error: {
        code: 'PHOTO_TOO_LARGE',
        message: `Foto tetap lebih besar dari ${Math.round(MAX_BYTES / 1024)} KB setelah dikompres. Pilih foto lain.`,
      },
    }
  }
  return { ok: true, data: best }
}
