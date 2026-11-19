// Logika murni untuk foto: ukuran, urutan percobaan kompresi, path, dan pesan galat (FR-013).

export const MAX_SIDE = 1600
export const TARGET_BYTES = 200 * 1024
// Toleransi 10 persen di atas target sebelum mencoba kualitas lebih rendah.
export const ACCEPT_BYTES = Math.round(TARGET_BYTES * 1.1)
// Sama dengan file_size_limit bucket kps-photos.
export const MAX_BYTES = 614_400
export const QUALITY_STEPS = [0.85, 0.75, 0.65, 0.55, 0.45, 0.35] as const
export const MIN_SCALE = 0.4

export interface Dimensions {
  width: number
  height: number
}

export function fitWithin(width: number, height: number, max: number = MAX_SIDE): Dimensions {
  const longest = Math.max(width, height)
  const ratio = longest > max ? max / longest : 1
  return {
    width: Math.max(1, Math.round(width * ratio)),
    height: Math.max(1, Math.round(height * ratio)),
  }
}

export function dimensionsFor(width: number, height: number, scale: number): Dimensions {
  const base = fitWithin(width, height)
  return {
    width: Math.max(1, Math.round(base.width * scale)),
    height: Math.max(1, Math.round(base.height * scale)),
  }
}

export interface Step {
  quality: number
  scale: number
}

export const firstStep = (): Step => ({ quality: QUALITY_STEPS[0], scale: 1 })

const round2 = (n: number) => Math.round(n * 100) / 100

// Turunkan kualitas dulu; bila habis, kecilkan dimensi 15 persen dan ulangi dari kualitas kedua.
export function nextStep(step: Step): Step | null {
  const qualities: readonly number[] = QUALITY_STEPS
  const i = qualities.indexOf(step.quality)
  if (i >= 0 && i < qualities.length - 1) return { quality: qualities[i + 1], scale: step.scale }
  const scale = round2(step.scale * 0.85)
  return scale < MIN_SCALE ? null : { quality: qualities[1], scale }
}

export const isAcceptable = (bytes: number) => bytes <= ACCEPT_BYTES
export const isWithinLimit = (bytes: number) => bytes <= MAX_BYTES

export function extensionFor(mime: string): 'webp' | 'jpg' {
  return mime === 'image/webp' ? 'webp' : 'jpg'
}

// Path baru setiap unggahan: <workspace_id>/<uuid>.<ekstensi>, huruf kecil (FR-013).
export function newPhotoPath(
  workspaceId: string,
  mime: string,
  uuid: () => string = () => crypto.randomUUID(),
): string {
  return `${workspaceId.toLowerCase()}/${uuid().toLowerCase()}.${extensionFor(mime)}`
}

export function describeUploadError(e: { message?: string; statusCode?: string | number } | null): string {
  const text = `${e?.message ?? ''} ${e?.statusCode ?? ''}`
  if (/failed to fetch|networkerror|load failed|network request failed/i.test(text)) {
    return 'Tidak ada koneksi internet.'
  }
  if (/exceeded|too large|payload|413/i.test(text)) return 'Foto melebihi batas 600 KB.'
  if (/mime|content.?type|not supported|415/i.test(text)) return 'Jenis berkas tidak diizinkan, hanya JPEG atau WebP.'
  if (/row-level security|unauthorized|not authorized|forbidden|403|401/i.test(text)) {
    return 'Anda tidak berhak mengunggah foto, atau sesi login berakhir.'
  }
  if (/already exists|duplicate|409/i.test(text)) return 'Berkas dengan nama itu sudah ada. Coba lagi.'
  return 'Foto gagal diunggah. Coba lagi beberapa saat.'
}
