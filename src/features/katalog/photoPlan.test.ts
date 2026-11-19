import { describe, expect, it } from 'vitest'
import {
  ACCEPT_BYTES,
  MAX_BYTES,
  MIN_SCALE,
  QUALITY_STEPS,
  describeUploadError,
  dimensionsFor,
  firstStep,
  fitWithin,
  isAcceptable,
  isWithinLimit,
  newPhotoPath,
  nextStep,
  type Step,
} from './photoPlan'

describe('fitWithin', () => {
  it.each([
    [4000, 3000, 1600, 1200],
    [3000, 4000, 1200, 1600],
    [800, 600, 800, 600],
    [1600, 1600, 1600, 1600],
    [10000, 1, 1600, 1],
  ])('%i x %i menjadi %i x %i', (w, h, ew, eh) => {
    expect(fitWithin(w, h)).toEqual({ width: ew, height: eh })
  })
  it('tidak memperbesar gambar kecil', () => {
    expect(fitWithin(100, 50)).toEqual({ width: 100, height: 50 })
  })
})

describe('dimensionsFor', () => {
  it('menerapkan skala setelah batas 1600 px', () => {
    expect(dimensionsFor(4000, 3000, 0.5)).toEqual({ width: 800, height: 600 })
  })
  it('tidak pernah lebih kecil dari 1 px', () => {
    expect(dimensionsFor(10000, 1, 0.4).height).toBe(1)
  })
})

describe('nextStep', () => {
  const walk = (): Step[] => {
    const out: Step[] = []
    for (let s: Step | null = firstStep(); s; s = nextStep(s)) out.push(s)
    return out
  }
  it('mulai dari kualitas tertinggi pada skala penuh', () => {
    expect(firstStep()).toEqual({ quality: QUALITY_STEPS[0], scale: 1 })
  })
  it('menurunkan kualitas dulu pada skala yang sama', () => {
    const s = walk()
    expect(s.slice(0, QUALITY_STEPS.length).map((x) => x.quality)).toEqual([...QUALITY_STEPS])
    expect(s.slice(0, QUALITY_STEPS.length).every((x) => x.scale === 1)).toBe(true)
  })
  it('berakhir, dan skala tidak pernah di bawah batas minimum', () => {
    const s = walk()
    expect(s.length).toBeGreaterThan(QUALITY_STEPS.length)
    expect(s.length).toBeLessThan(40)
    expect(s.every((x) => x.scale >= MIN_SCALE)).toBe(true)
    expect(nextStep(s[s.length - 1])).toBeNull()
  })
  it('skala turun setelah kualitas habis', () => {
    const s = walk()
    expect(s[QUALITY_STEPS.length].scale).toBeLessThan(1)
  })
})

describe('batas ukuran', () => {
  it('menerima sampai toleransi target, menolak di atasnya', () => {
    expect(isAcceptable(ACCEPT_BYTES)).toBe(true)
    expect(isAcceptable(ACCEPT_BYTES + 1)).toBe(false)
  })
  it('batas keras sama dengan batas bucket 614.400 byte', () => {
    expect(MAX_BYTES).toBe(614400)
    expect(isWithinLimit(614400)).toBe(true)
    expect(isWithinLimit(614401)).toBe(false)
  })
})

describe('newPhotoPath', () => {
  const uuid = () => 'ABCDEF01-2345-6789-ABCD-EF0123456789'
  it('membentuk path huruf kecil dengan ekstensi sesuai jenis', () => {
    expect(newPhotoPath('AAAAAAAA-0000-0000-0000-000000000001', 'image/webp', uuid)).toBe(
      'aaaaaaaa-0000-0000-0000-000000000001/abcdef01-2345-6789-abcd-ef0123456789.webp',
    )
    expect(newPhotoPath('w', 'image/jpeg', uuid)).toMatch(/\.jpg$/)
  })
  it('setiap panggilan bawaan menghasilkan path berbeda', () => {
    const a = newPhotoPath('w', 'image/webp')
    const b = newPhotoPath('w', 'image/webp')
    expect(a).not.toBe(b)
    expect(a).toMatch(/^w\/[0-9a-f-]{36}\.webp$/)
  })
})

describe('describeUploadError', () => {
  it.each([
    [{ message: 'Failed to fetch' }, 'koneksi'],
    [{ message: 'The object exceeded the maximum allowed size' }, '600 KB'],
    [{ message: 'mime type image/png is not supported' }, 'JPEG atau WebP'],
    [{ message: 'new row violates row-level security policy' }, 'tidak berhak'],
    [{ message: 'The resource already exists', statusCode: '409' }, 'sudah ada'],
    [{ message: 'boom' }, 'gagal diunggah'],
    [null, 'gagal diunggah'],
  ])('memetakan %j', (raw, fragment) => {
    expect(describeUploadError(raw)).toContain(fragment)
  })
})
