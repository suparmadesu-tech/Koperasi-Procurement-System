#!/usr/bin/env bash
# Tahap 2, Bagian 3: pengelolaan katalog oleh Admin (kategori, satuan, barang) dan foto.
# Jalankan dari akar repo setelah Bagian 1 dan 2: bash tahap2-bagian3-sesuai.sh
# DISESUAIKAN: pembungkus halaman tanpa padding sendiri (Layout.tsx sudah memberi margin dan jarak menu bawah).
set -euo pipefail

OUT_DIR="src/features/katalog"
PAGE_FILE="${PAGE_FILE:-src/pages/AdminArea.tsx}"
UI_FILE="${UI_FILE:-src/components/ui.ts}"
SUPABASE_FILE="${SUPABASE_FILE:-src/lib/supabase.ts}"

fail() { echo "BERHENTI, tidak ada yang diubah: $*" >&2; exit 1; }

# 1. Pemeriksaan awal (tanpa menulis apa pun)
command -v node >/dev/null || fail "node tidak ditemukan."
[ -f package.json ] || fail "jalankan dari akar repo."
for f in "$PAGE_FILE" "$UI_FILE" "$SUPABASE_FILE" \
  "$OUT_DIR/useCatalog.ts" "$OUT_DIR/search.ts" "$OUT_DIR/validation.ts" "$OUT_DIR/catalogWrite.ts" \
  "$OUT_DIR/catalogStore.ts" "$OUT_DIR/rows.ts" "$OUT_DIR/viewModel.ts" "$OUT_DIR/photo.ts" "$OUT_DIR/types.ts"; do
  [ -f "$f" ] || fail "berkas $f tidak ditemukan (Bagian 1 dan 2 sudah dijalankan?)."
done
has_export() { grep -Eq "export[[:space:]]+(async[[:space:]]+)?(const|function|let|interface|type)[[:space:]]+$2\b" "$1"; }
need() { has_export "$1" "$2" || fail "$2 tidak diekspor oleh $1."; }
need "$OUT_DIR/useCatalog.ts" useCatalog
for n in filterProducts indexById compareByName selectableOptions; do need "$OUT_DIR/search.ts" "$n"; done
for n in validateCategoryForm validateUnitForm validateProductForm; do need "$OUT_DIR/validation.ts" "$n"; done
for n in createCategory updateCategory createUnit updateUnit createProduct updateProduct; do need "$OUT_DIR/catalogWrite.ts" "$n"; done
need "$OUT_DIR/catalogStore.ts" isOnline
need "$OUT_DIR/rows.ts" ProductPatch
for n in describeProduct pageSlice PAGE_STEP; do need "$OUT_DIR/viewModel.ts" "$n"; done
need "$OUT_DIR/photo.ts" usePhotoUrl
for n in btnPrimary btnSecondary inputClass; do need "$UI_FILE" "$n"; done
need "$SUPABASE_FILE" supabase

ROUTER="$(node -e "
const p=require('./package.json');const d={...p.dependencies,...p.devDependencies};
console.log(d['react-router-dom']?'react-router-dom':d['react-router']?'react-router':'')")"
[ -n "$ROUTER" ] || fail "react-router-dom atau react-router tidak ada di package.json."

AUTH_FILES="$(grep -rlE "export[[:space:]]+(const|function)[[:space:]]+useAuth\b" src || true)"
[ "$(printf '%s\n' "$AUTH_FILES" | grep -c .)" = "1" ] \
  || fail "useAuth harus diekspor tepat satu berkas di src/, ditemukan: ${AUTH_FILES:-tidak ada}."
AUTH_FILE="$AUTH_FILES"

for n in photoPlan productDiff photoCompress photoUpload useOnline formUi TaxonomyAdmin ProductForm ProductAdmin AdminView; do
  [ ! -e "$OUT_DIR/$n.ts" ] && [ ! -e "$OUT_DIR/$n.tsx" ] || fail "$OUT_DIR/$n sudah ada; skrip tidak menimpa berkas."
done
for n in photoPlan productDiff; do
  [ ! -e "$OUT_DIR/$n.test.ts" ] || fail "$OUT_DIR/$n.test.ts sudah ada."
done

relfrom() { node -e "
const p=require('path');
let r=p.relative(process.argv[1],process.argv[2]).split(p.sep).join('/').replace(/\.tsx?$/,'');
console.log(r.startsWith('.')?r:'./'+r)" "$1" "$2"; }
REL_UI="$(relfrom "$OUT_DIR" "$UI_FILE")"
REL_SUPABASE="$(relfrom "$OUT_DIR" "$SUPABASE_FILE")"
REL_AUTH="$(relfrom "$(dirname "$PAGE_FILE")" "$AUTH_FILE")"
REL_VIEW="$(relfrom "$(dirname "$PAGE_FILE")" "$OUT_DIR/AdminView")"

# 2. Patch halaman AdminArea: harus placeholder dengan satu ekspor AdminArea
PATCH_JS="$(mktemp)"
trap 'rm -f "$PATCH_JS"' EXIT
cat > "$PATCH_JS" <<'PATCH_END'
const fs = require('fs')
const file = process.argv[2]
const src = fs.readFileSync(file, 'utf8')
if (src.includes('kps:admin-katalog')) {
  console.error(file + ' sudah berisi layar admin katalog (penanda kps:admin-katalog).')
  process.exit(1)
}
const lines = src.split('\n').length
const kinds = [
  ['default', /export\s+default\s+function\s+AdminArea\b/g],
  ['named', /export\s+function\s+AdminArea\b/g],
  ['named', /export\s+const\s+AdminArea\b/g],
]
const hits = kinds.flatMap(([k, re]) => [...src.matchAll(re)].map(() => k))
if (hits.length !== 1 || lines > 60) {
  console.error(
    file + ': bukan placeholder yang dikenali (ekspor AdminArea cocok ' + hits.length +
      ' kali, ' + lines + ' baris; syarat: tepat 1 kali dan paling banyak 60 baris).',
  )
  process.exit(1)
}
console.log(hits[0])
PATCH_END
EXPORT_KIND="$(node "$PATCH_JS" "$PAGE_FILE")" || fail "patch $PAGE_FILE ditolak (lihat pesan di atas)."
if [ "$EXPORT_KIND" = "default" ]; then EXPORT_DECL="export default function"; else EXPORT_DECL="export function"; fi

# 3. Berkas baru
cat > "$OUT_DIR/photoPlan.ts" <<'TS_END'
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
TS_END

cat > "$OUT_DIR/photoPlan.test.ts" <<'TS_END'
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
TS_END

cat > "$OUT_DIR/productDiff.ts" <<'TS_END'
import type { ProductPatch } from './rows'
import type { ProductRow } from './types'
import type { ProductFormValue } from './validation'

const normalizePrice = (p: string | null) => (p === null ? null : p.replace(/\.0+$/, ''))

// Hanya kolom yang berubah yang dikirim, supaya UPDATE tidak menyentuh kolom lain.
export function diffProduct(current: ProductRow, next: ProductFormValue, archived: boolean): ProductPatch {
  const patch: ProductPatch = {}
  if (next.name !== current.name) patch.name = next.name
  if (next.categoryId !== current.category_id) patch.categoryId = next.categoryId
  if (next.unitId !== current.unit_id) patch.unitId = next.unitId
  if (normalizePrice(next.price) !== normalizePrice(current.price)) patch.price = next.price
  if (archived !== current.is_archived) patch.isArchived = archived
  return patch
}
TS_END

cat > "$OUT_DIR/productDiff.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { diffProduct } from './productDiff'
import type { ProductRow } from './types'

const current: ProductRow = {
  id: 'p',
  workspace_id: 'w',
  category_id: 'c1',
  unit_id: 'u1',
  name: 'Gula',
  photo_path: null,
  price: '12500',
  is_archived: false,
  updated_at: '2026-11-18T00:00:00Z',
}
const same = { name: 'Gula', categoryId: 'c1', unitId: 'u1', price: '12500' }

describe('diffProduct', () => {
  it('tidak ada perubahan menghasilkan objek kosong', () => {
    expect(diffProduct(current, same, false)).toEqual({})
  })
  it('hanya memuat kolom yang berubah', () => {
    expect(diffProduct(current, { ...same, name: 'Gula Pasir', unitId: 'u2' }, false)).toEqual({
      name: 'Gula Pasir',
      unitId: 'u2',
    })
  })
  it('mengosongkan harga mengirim null, harga 0 dianggap perubahan', () => {
    expect(diffProduct(current, { ...same, price: null }, false)).toEqual({ price: null })
    expect(diffProduct(current, { ...same, price: '0' }, false)).toEqual({ price: '0' })
  })
  it('harga sama dengan sisa nol desimal dari server tidak dianggap berubah', () => {
    expect(diffProduct({ ...current, price: '12500.00' }, same, false)).toEqual({})
  })
  it('mengarsipkan dan mengaktifkan kembali', () => {
    expect(diffProduct(current, same, true)).toEqual({ isArchived: true })
    expect(diffProduct({ ...current, is_archived: true }, same, false)).toEqual({ isArchived: false })
  })
})
TS_END

cat > "$OUT_DIR/photoCompress.ts" <<'TS_END'
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
TS_END

cat > "$OUT_DIR/photoUpload.ts" <<'TS_END'
import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '@@SUPABASE@@'
import { isOnline } from './catalogStore'
import { describeUploadError, newPhotoPath } from './photoPlan'
import type { Result } from './types'

const BUCKET = 'kps-photos'
const sb = supabase as unknown as SupabaseClient | null

// Selalu path baru dan tanpa upsert: berkas yang dirujuk snapshot tidak boleh tertimpa (BR-027).
export async function uploadProductPhoto(workspaceId: string, blob: Blob, mime: string): Promise<Result<string>> {
  if (!isOnline()) {
    return { ok: false, error: { code: 'OFFLINE', message: 'Mengunggah foto memerlukan koneksi internet.' } }
  }
  if (!sb) {
    return { ok: false, error: { code: 'NO_CLIENT', message: 'Supabase belum dikonfigurasi.' } }
  }
  const path = newPhotoPath(workspaceId, mime)
  try {
    const { error } = await sb.storage
      .from(BUCKET)
      .upload(path, blob, { contentType: mime, upsert: false, cacheControl: '31536000' })
    if (error) {
      return {
        ok: false,
        error: { code: 'UPLOAD_FAILED', message: describeUploadError(error as { message?: string }) },
      }
    }
    return { ok: true, data: path }
  } catch (e) {
    return {
      ok: false,
      error: { code: 'UPLOAD_FAILED', message: describeUploadError(e as { message?: string }) },
    }
  }
}
TS_END

cat > "$OUT_DIR/useOnline.ts" <<'TS_END'
import { useSyncExternalStore } from 'react'

function subscribe(listener: () => void) {
  window.addEventListener('online', listener)
  window.addEventListener('offline', listener)
  return () => {
    window.removeEventListener('online', listener)
    window.removeEventListener('offline', listener)
  }
}

export function useOnline(): boolean {
  return useSyncExternalStore(subscribe, () => navigator.onLine, () => true)
}
TS_END

cat > "$OUT_DIR/formUi.tsx" <<'TSX_END'
import { useId, type ReactNode } from 'react'

export const labelClass = 'mb-1 block text-sm font-medium text-slate-800'

export function Field({
  label,
  error,
  hint,
  children,
}: {
  label: string
  error?: string
  hint?: string
  children: (p: { id: string; describedBy: string | undefined; invalid: boolean }) => ReactNode
}) {
  const id = useId()
  const hintId = `${id}-hint`
  const errorId = `${id}-error`
  const describedBy = [hint ? hintId : '', error ? errorId : ''].filter(Boolean).join(' ') || undefined
  return (
    <div>
      <label htmlFor={id} className={labelClass}>
        {label}
      </label>
      {children({ id, describedBy, invalid: Boolean(error) })}
      {hint && (
        <p id={hintId} className="mt-1 text-sm text-slate-600">
          {hint}
        </p>
      )}
      {error && (
        <p id={errorId} className="mt-1 text-sm text-red-800">
          {error}
        </p>
      )}
    </div>
  )
}

export type Flash = { kind: 'ok' | 'error'; text: string } | null

export function FlashMessage({ flash }: { flash: Flash }) {
  if (!flash) return null
  return (
    <p
      role={flash.kind === 'error' ? 'alert' : 'status'}
      className={`text-sm ${flash.kind === 'error' ? 'text-red-800' : 'text-emerald-800'}`}
    >
      {flash.text}
    </p>
  )
}
TSX_END

cat > "$OUT_DIR/TaxonomyAdmin.tsx" <<'TSX_END'
import { useState, type FormEvent } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '@@UI@@'
import { createCategory, createUnit, updateCategory, updateUnit } from './catalogWrite'
import { Field, FlashMessage, type Flash } from './formUi'
import { compareByName } from './search'
import type { CategoryRow } from './types'
import { validateCategoryForm, validateUnitForm } from './validation'

type Kind = 'category' | 'unit'
type Row = CategoryRow & { allow_fraction?: boolean }

const WORDS = {
  category: { title: 'Kategori', add: 'Tambah kategori', added: 'Kategori ditambahkan.', saved: 'Kategori disimpan.' },
  unit: { title: 'Satuan', add: 'Tambah satuan', added: 'Satuan ditambahkan.', saved: 'Satuan disimpan.' },
} as const

export function TaxonomyAdmin({
  kind,
  workspaceId,
  rows,
  online,
}: {
  kind: Kind
  workspaceId: string
  rows: readonly Row[]
  online: boolean
}) {
  const words = WORDS[kind]
  const [addName, setAddName] = useState('')
  const [addFraction, setAddFraction] = useState(false)
  const [addError, setAddError] = useState<string | undefined>()
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [editFraction, setEditFraction] = useState(false)
  const [editError, setEditError] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [flash, setFlash] = useState<Flash>(null)

  // Mengembalikan pesan galat, atau null bila server menerima.
  async function submit(id: string | null, name: string, allowFraction: boolean): Promise<string | null> {
    if (kind === 'unit') {
      const v = validateUnitForm({ name, allowFraction })
      if (!v.ok) return v.errors.name ?? 'Isian tidak valid.'
      const r = id ? await updateUnit(workspaceId, id, v.value) : await createUnit(workspaceId, v.value)
      return r.ok ? null : r.error.message
    }
    const v = validateCategoryForm({ name })
    if (!v.ok) return v.errors.name ?? 'Isian tidak valid.'
    const r = id ? await updateCategory(workspaceId, id, v.value) : await createCategory(workspaceId, v.value)
    return r.ok ? null : r.error.message
  }

  async function onAdd(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    setBusy(true)
    setFlash(null)
    const error = await submit(null, addName, addFraction)
    setBusy(false)
    if (error) {
      setAddError(error)
      return
    }
    setAddError(undefined)
    setAddName('')
    setAddFraction(false)
    setFlash({ kind: 'ok', text: words.added })
  }

  async function onEdit(e: FormEvent) {
    e.preventDefault()
    if (busy || !editingId) return
    setBusy(true)
    setFlash(null)
    const error = await submit(editingId, editName, editFraction)
    setBusy(false)
    if (error) {
      setEditError(error)
      return
    }
    setEditingId(null)
    setEditError(undefined)
    setFlash({ kind: 'ok', text: words.saved })
  }

  async function toggleArchive(row: Row) {
    if (busy) return
    setBusy(true)
    setFlash(null)
    const patch = { is_archived: !row.is_archived }
    const r = kind === 'unit' ? await updateUnit(workspaceId, row.id, patch) : await updateCategory(workspaceId, row.id, patch)
    setBusy(false)
    setFlash(
      r.ok
        ? { kind: 'ok', text: row.is_archived ? 'Diaktifkan kembali.' : 'Diarsipkan.' }
        : { kind: 'error', text: r.error.message },
    )
  }

  function startEdit(row: Row) {
    setEditingId(row.id)
    setEditName(row.name)
    setEditFraction(Boolean(row.allow_fraction))
    setEditError(undefined)
    setFlash(null)
  }

  const sorted = [...rows].sort((a, b) => Number(a.is_archived) - Number(b.is_archived) || compareByName(a, b))
  const fractionBox = (checked: boolean, onChange: (v: boolean) => void) => (
    <label className="flex min-h-11 items-center gap-3 text-sm text-slate-900">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="h-5 w-5" />
      Boleh jumlah pecahan (misalnya 0,5)
    </label>
  )

  return (
    <section aria-label={words.title} className="space-y-6">
      <form onSubmit={onAdd} className="space-y-3 rounded-md border border-slate-300 p-4">
        <fieldset disabled={!online || busy} className="space-y-3">
          <Field label={`Nama ${words.title.toLowerCase()} baru`} error={addError}>
            {(p) => (
              <input
                id={p.id}
                value={addName}
                onChange={(e) => setAddName(e.target.value)}
                aria-invalid={p.invalid}
                aria-describedby={p.describedBy}
                autoComplete="off"
                className={inputClass}
              />
            )}
          </Field>
          {kind === 'unit' && fractionBox(addFraction, setAddFraction)}
          <button type="submit" className={btnPrimary}>
            {words.add}
          </button>
        </fieldset>
        <FlashMessage flash={flash} />
      </form>

      {sorted.length === 0 ? (
        <p className="text-sm text-slate-700">Belum ada {words.title.toLowerCase()}.</p>
      ) : (
        <ul className="divide-y divide-slate-200 border-y border-slate-200">
          {sorted.map((row) =>
            editingId === row.id ? (
              <li key={row.id} className="py-3">
                <form onSubmit={onEdit} className="space-y-3">
                  <fieldset disabled={!online || busy} className="space-y-3">
                    <Field label={`Nama ${words.title.toLowerCase()}`} error={editError}>
                      {(p) => (
                        <input
                          id={p.id}
                          value={editName}
                          onChange={(e) => setEditName(e.target.value)}
                          aria-invalid={p.invalid}
                          aria-describedby={p.describedBy}
                          autoComplete="off"
                          autoFocus
                          className={inputClass}
                        />
                      )}
                    </Field>
                    {kind === 'unit' && fractionBox(editFraction, setEditFraction)}
                    {kind === 'unit' && (
                      <p className="text-sm text-slate-600">
                        Perubahan ini hanya berlaku untuk input baru. Data lama tidak diubah.
                      </p>
                    )}
                    <div className="flex gap-3">
                      <button type="submit" className={btnPrimary}>
                        Simpan
                      </button>
                      <button type="button" onClick={() => setEditingId(null)} className={btnSecondary}>
                        Batal
                      </button>
                    </div>
                  </fieldset>
                </form>
              </li>
            ) : (
              <li key={row.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                <div className="min-w-0">
                  <p className="break-words font-medium text-slate-900">{row.name}</p>
                  <p className="text-sm text-slate-600">
                    {kind === 'unit' && (row.allow_fraction ? 'Boleh pecahan' : 'Hanya bilangan bulat')}
                    {kind === 'unit' && row.is_archived && ' / '}
                    {row.is_archived && 'Diarsipkan'}
                  </p>
                </div>
                <div className="flex gap-2">
                  <button type="button" disabled={!online || busy} onClick={() => startEdit(row)} className={btnSecondary}>
                    Ubah
                  </button>
                  <button
                    type="button"
                    disabled={!online || busy}
                    onClick={() => void toggleArchive(row)}
                    className={btnSecondary}
                  >
                    {row.is_archived ? 'Aktifkan' : 'Arsipkan'}
                  </button>
                </div>
              </li>
            ),
          )}
        </ul>
      )}
    </section>
  )
}
TSX_END

cat > "$OUT_DIR/ProductForm.tsx" <<'TSX_END'
import { useEffect, useState, type ChangeEvent, type FormEvent } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '@@UI@@'
import { createProduct, updateProduct } from './catalogWrite'
import { Field, FlashMessage, type Flash } from './formUi'
import { compressImage } from './photoCompress'
import { usePhotoUrl } from './photo'
import { uploadProductPhoto } from './photoUpload'
import { diffProduct } from './productDiff'
import { selectableOptions } from './search'
import type { CategoryRow, ProductRow, UnitRow } from './types'
import { validateProductForm } from './validation'

interface Prepared {
  blob: Blob
  mime: string
  url: string
}

type FieldErrors = Partial<Record<'name' | 'categoryId' | 'unitId' | 'price' | 'photo', string>>

function CurrentPhoto({ path, name }: { path: string | null; name: string }) {
  const { state, retry, reportImageError } = usePhotoUrl(path)
  if (state.kind === 'ready') {
    return (
      <img
        src={state.url}
        alt={name}
        width={160}
        height={120}
        onError={reportImageError}
        className="h-[120px] w-[160px] rounded-md bg-slate-100 object-contain"
      />
    )
  }
  const note =
    state.kind === 'none'
      ? 'Belum ada foto.'
      : state.kind === 'loading'
        ? 'Memuat foto...'
        : state.kind === 'offline'
          ? 'Foto tidak tersedia saat offline.'
          : 'Foto gagal dimuat.'
  return (
    <div className="flex items-center gap-3 text-sm text-slate-700">
      <span>{note}</span>
      {(state.kind === 'offline' || state.kind === 'error') && (
        <button type="button" onClick={retry} className={btnSecondary}>
          Coba lagi
        </button>
      )}
    </div>
  )
}

export function ProductForm({
  workspaceId,
  product,
  categories,
  units,
  online,
  onClose,
}: {
  workspaceId: string
  product: ProductRow | null
  categories: readonly CategoryRow[]
  units: readonly UnitRow[]
  online: boolean
  onClose: (message?: string) => void
}) {
  // Setelah INSERT berhasil, formulir beralih ke mode ubah agar percobaan ulang tidak membuat barang ganda.
  const [current, setCurrent] = useState<ProductRow | null>(product)
  const [name, setName] = useState(product?.name ?? '')
  const [categoryId, setCategoryId] = useState(product?.category_id ?? '')
  const [unitId, setUnitId] = useState(product?.unit_id ?? '')
  const [priceText, setPriceText] = useState(product?.price ?? '')
  const [archived, setArchived] = useState(product?.is_archived ?? false)
  const [photo, setPhoto] = useState<Prepared | null>(null)
  const [pendingPath, setPendingPath] = useState<string | null>(null)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [flash, setFlash] = useState<Flash>(null)
  const [busy, setBusy] = useState(false)
  const [preparing, setPreparing] = useState(false)

  useEffect(() => {
    if (!photo) return undefined
    return () => URL.revokeObjectURL(photo.url)
  }, [photo])

  const categoryOptions = selectableOptions(categories, product?.category_id)
  const unitOptions = selectableOptions(units, product?.unit_id)

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setPreparing(true)
    setErrors((prev) => ({ ...prev, photo: undefined }))
    const r = await compressImage(file)
    setPreparing(false)
    if (!r.ok) {
      setErrors((prev) => ({ ...prev, photo: r.error.message }))
      return
    }
    setPendingPath(null)
    setPhoto({ blob: r.data.blob, mime: r.data.mime, url: URL.createObjectURL(r.data.blob) })
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (busy || preparing) return
    const v = validateProductForm({ name, categoryId, unitId, priceText })
    if (!v.ok) {
      setErrors((prev) => ({ ...v.errors, photo: prev.photo }))
      setFlash(null)
      return
    }
    setErrors({})
    setFlash(null)
    setBusy(true)

    let saved = current
    let changed = false
    if (!saved) {
      const r = await createProduct(workspaceId, v.value)
      if (!r.ok) {
        setBusy(false)
        setFlash({ kind: 'error', text: r.error.message })
        return
      }
      saved = r.data
      changed = true
      setCurrent(saved)
    } else {
      const patch = diffProduct(saved, v.value, archived)
      if (Object.keys(patch).length > 0) {
        const r = await updateProduct(workspaceId, saved.id, patch)
        if (!r.ok) {
          setBusy(false)
          setFlash({ kind: 'error', text: r.error.message })
          return
        }
        saved = r.data
        changed = true
        setCurrent(saved)
      }
    }

    if (photo || pendingPath) {
      let path = pendingPath
      if (!path && photo) {
        const up = await uploadProductPhoto(workspaceId, photo.blob, photo.mime)
        if (!up.ok) {
          setBusy(false)
          setFlash({ kind: 'error', text: `Data barang tersimpan, tetapi foto gagal diunggah: ${up.error.message}` })
          return
        }
        path = up.data
        setPendingPath(path)
      }
      const r = await updateProduct(workspaceId, saved.id, { photoPath: path as string })
      if (!r.ok) {
        setBusy(false)
        setFlash({
          kind: 'error',
          text: `Foto sudah terunggah tetapi belum terpasang pada barang: ${r.error.message} Tekan Simpan lagi untuk memasangnya.`,
        })
        return
      }
      setCurrent(r.data)
      setPhoto(null)
      setPendingPath(null)
      changed = true
    }

    setBusy(false)
    onClose(changed ? 'Barang tersimpan.' : 'Tidak ada perubahan.')
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <h2 className="text-lg font-semibold text-slate-900">{product ? 'Ubah barang' : 'Tambah barang'}</h2>
      <fieldset disabled={!online || busy} className="space-y-4">
        <Field label="Nama barang" error={errors.name}>
          {(p) => (
            <input
              id={p.id}
              value={name}
              onChange={(e) => setName(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              autoComplete="off"
              className={inputClass}
            />
          )}
        </Field>
        <Field label="Kategori" error={errors.categoryId}>
          {(p) => (
            <select
              id={p.id}
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className={inputClass}
            >
              <option value="">Pilih kategori</option>
              {categoryOptions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                  {c.is_archived ? ' (Diarsipkan)' : ''}
                </option>
              ))}
            </select>
          )}
        </Field>
        <Field label="Satuan" error={errors.unitId}>
          {(p) => (
            <select
              id={p.id}
              value={unitId}
              onChange={(e) => setUnitId(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className={inputClass}
            >
              <option value="">Pilih satuan</option>
              {unitOptions.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name}
                  {u.is_archived ? ' (Diarsipkan)' : ''}
                </option>
              ))}
            </select>
          )}
        </Field>
        <Field
          label="Harga satuan (Rupiah, opsional)"
          error={errors.price}
          hint="Kosongkan bila harga belum diketahui. Harga 0 dianggap harga."
        >
          {(p) => (
            <input
              id={p.id}
              value={priceText}
              onChange={(e) => setPriceText(e.target.value)}
              inputMode="numeric"
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              autoComplete="off"
              className={inputClass}
            />
          )}
        </Field>

        <Field
          label="Foto (opsional)"
          error={errors.photo}
          hint="Dikompres otomatis di perangkat menjadi sekitar 200 KB."
        >
          {(p) => (
            <input
              id={p.id}
              type="file"
              accept="image/*"
              onChange={onPick}
              disabled={preparing}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className="block w-full text-sm text-slate-800 file:mr-3 file:min-h-11 file:rounded-md file:border file:border-slate-300 file:bg-white file:px-4 file:text-slate-900"
            />
          )}
        </Field>
        <div aria-live="polite">
          {preparing && <p className="text-sm text-slate-700">Memproses foto...</p>}
          {photo ? (
            <div className="flex items-end gap-3">
              <img
                src={photo.url}
                alt="Foto baru yang akan disimpan"
                width={160}
                height={120}
                className="h-[120px] w-[160px] rounded-md bg-slate-100 object-contain"
              />
              <div className="text-sm text-slate-700">
                <p>{Math.round(photo.blob.size / 1024)} KB, belum disimpan.</p>
                <button type="button" onClick={() => setPhoto(null)} className={`${btnSecondary} mt-2`}>
                  Batal pilih foto
                </button>
              </div>
            </div>
          ) : (
            current && <CurrentPhoto path={current.photo_path} name={current.name} />
          )}
        </div>

        {product && (
          <label className="flex min-h-11 items-center gap-3 text-sm text-slate-900">
            <input
              type="checkbox"
              checked={archived}
              onChange={(e) => setArchived(e.target.checked)}
              className="h-5 w-5"
            />
            Diarsipkan (tidak muncul untuk penambahan baru)
          </label>
        )}
      </fieldset>

      {!online && (
        <p role="status" className="text-sm text-slate-700">
          Offline. Perubahan katalog memerlukan koneksi internet.
        </p>
      )}
      <FlashMessage flash={flash} />
      <div className="flex gap-3">
        <button type="submit" disabled={!online || busy || preparing} className={`${btnPrimary} flex-1 sm:flex-none`}>
          {busy ? 'Menyimpan...' : 'Simpan'}
        </button>
        <button type="button" disabled={busy} onClick={() => onClose()} className={`${btnSecondary} flex-1 sm:flex-none`}>
          {current && !product ? 'Selesai' : 'Batal'}
        </button>
      </div>
    </form>
  )
}
TSX_END

cat > "$OUT_DIR/ProductAdmin.tsx" <<'TSX_END'
import { useEffect, useMemo, useState } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '@@UI@@'
import { Field, FlashMessage, type Flash } from './formUi'
import { ProductForm } from './ProductForm'
import { filterProducts, indexById, selectableOptions } from './search'
import type { CatalogData, ProductRow } from './types'
import { describeProduct, pageSlice, PAGE_STEP } from './viewModel'

export function ProductAdmin({
  workspaceId,
  data,
  online,
}: {
  workspaceId: string
  data: CatalogData
  online: boolean
}) {
  const [editing, setEditing] = useState<{ product: ProductRow | null } | null>(null)
  const [query, setQuery] = useState('')
  const [limit, setLimit] = useState(PAGE_STEP)
  const [flash, setFlash] = useState<Flash>(null)

  const categories = useMemo(() => indexById(data.categories), [data.categories])
  const units = useMemo(() => indexById(data.units), [data.units])
  const filtered = useMemo(() => filterProducts(data.products, { query, archive: 'all' }), [data.products, query])
  const { shown, remaining } = pageSlice(filtered, limit)
  const canAdd = selectableOptions(data.categories).length > 0 && selectableOptions(data.units).length > 0

  useEffect(() => {
    setLimit(PAGE_STEP)
  }, [query])

  if (editing) {
    return (
      <ProductForm
        key={editing.product?.id ?? 'baru'}
        workspaceId={workspaceId}
        product={editing.product}
        categories={data.categories}
        units={data.units}
        online={online}
        onClose={(message) => {
          setEditing(null)
          if (message) setFlash({ kind: 'ok', text: message })
        }}
      />
    )
  }

  return (
    <section aria-label="Barang" className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-0 flex-1 basis-56">
          <Field label="Cari barang">
            {(p) => (
              <input
                id={p.id}
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                autoComplete="off"
                className={inputClass}
              />
            )}
          </Field>
        </div>
        <button
          type="button"
          disabled={!online || !canAdd}
          onClick={() => {
            setFlash(null)
            setEditing({ product: null })
          }}
          className={btnPrimary}
        >
          Tambah barang
        </button>
      </div>
      {!canAdd && (
        <p className="text-sm text-slate-700">
          Buat minimal satu kategori dan satu satuan aktif sebelum menambah barang.
        </p>
      )}
      <FlashMessage flash={flash} />

      {data.products.length === 0 ? (
        <p className="text-sm text-slate-700">Belum ada barang di katalog.</p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-slate-900">Tidak ada barang yang cocok dengan pencarian ini.</p>
      ) : (
        <>
          <p aria-live="polite" className="text-sm text-slate-700">
            {filtered.length} barang
          </p>
          <ul className="divide-y divide-slate-200 border-y border-slate-200">
            {shown.map((p) => {
              const v = describeProduct(p, categories, units)
              return (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setFlash(null)
                      setEditing({ product: p })
                    }}
                    className="flex min-h-14 w-full items-start justify-between gap-3 px-1 py-3 text-left hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-slate-900"
                  >
                    <span className="min-w-0">
                      <span className="block break-words font-medium text-slate-900">{p.name}</span>
                      <span className="block break-words text-sm text-slate-600">
                        {v.categoryName} / {v.unitName}
                      </span>
                      {p.is_archived && (
                        <span className="mt-1 inline-block rounded-sm border border-slate-500 px-1.5 text-xs text-slate-800">
                          Diarsipkan
                        </span>
                      )}
                    </span>
                    <span className="max-w-[8rem] shrink-0 text-right text-sm tabular-nums text-slate-700">
                      {v.priceText ?? 'Harga belum tersedia'}
                    </span>
                  </button>
                </li>
              )
            })}
          </ul>
          {remaining > 0 && (
            <button type="button" onClick={() => setLimit((n) => n + PAGE_STEP)} className={`${btnSecondary} w-full`}>
              Tampilkan {Math.min(PAGE_STEP, remaining)} lagi (sisa {remaining})
            </button>
          )}
        </>
      )}
    </section>
  )
}
TSX_END

cat > "$OUT_DIR/AdminView.tsx" <<'TSX_END'
import { useState } from 'react'
import { Link } from '@@ROUTER@@'
import { btnSecondary } from '@@UI@@'
import { ProductAdmin } from './ProductAdmin'
import { TaxonomyAdmin } from './TaxonomyAdmin'
import { useCatalog } from './useCatalog'
import { useOnline } from './useOnline'

const TABS = [
  { id: 'barang', label: 'Barang' },
  { id: 'kategori', label: 'Kategori' },
  { id: 'satuan', label: 'Satuan' },
] as const
type TabId = (typeof TABS)[number]['id']

export function AdminView({ workspaceId }: { workspaceId: string }) {
  const { data, loading, readError } = useCatalog(workspaceId)
  const online = useOnline()
  const [tab, setTab] = useState<TabId>('barang')

  return (
    <div className="w-full">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-slate-900">Kelola katalog</h1>
        <Link to="/katalog" className={btnSecondary}>
          Lihat katalog
        </Link>
      </div>

      {!online && (
        <p role="status" className="mt-3 text-sm text-slate-800">
          Offline. Mengubah katalog memerlukan koneksi internet, jadi formulir dinonaktifkan.
        </p>
      )}

      <div role="group" aria-label="Bagian katalog" className="mt-4 flex gap-2">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            aria-pressed={tab === t.id}
            onClick={() => setTab(t.id)}
            className={`min-h-11 flex-1 rounded-md border px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-900 focus-visible:ring-offset-2 sm:flex-none sm:px-6 ${
              tab === t.id
                ? 'border-slate-900 bg-slate-900 text-white'
                : 'border-slate-300 bg-white text-slate-900 hover:bg-slate-50'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="mt-6">
        {readError ? (
          <p role="alert" className="text-sm text-red-800">
            Katalog di perangkat tidak dapat dibaca: {readError}
          </p>
        ) : loading || !data ? (
          <p role="status" className="text-sm text-slate-700">
            Memuat katalog dari perangkat...
          </p>
        ) : tab === 'barang' ? (
          <ProductAdmin workspaceId={workspaceId} data={data} online={online} />
        ) : tab === 'kategori' ? (
          <TaxonomyAdmin kind="category" workspaceId={workspaceId} rows={data.categories} online={online} />
        ) : (
          <TaxonomyAdmin kind="unit" workspaceId={workspaceId} rows={data.units} online={online} />
        )}
      </div>
    </div>
  )
}
TSX_END

cat > "$PAGE_FILE.new" <<'TSX_END'
// kps:admin-katalog
import { useAuth } from '@@AUTH@@'
import { AdminView } from '@@VIEW@@'

@@EXPORT@@ AdminArea() {
  const { state } = useAuth()
  if (state.status !== 'ready') return null
  if (state.role !== 'admin') {
    return <p className="text-sm text-slate-900">Halaman ini hanya untuk Admin.</p>
  }
  return <AdminView workspaceId={state.workspace.id} />
}
TSX_END

# 4. Isi jalur relatif
for f in "$OUT_DIR/photoUpload.ts" "$OUT_DIR/TaxonomyAdmin.tsx" "$OUT_DIR/ProductForm.tsx" \
  "$OUT_DIR/ProductAdmin.tsx" "$OUT_DIR/AdminView.tsx" "$PAGE_FILE.new"; do
  sed -i \
    -e "s#@@SUPABASE@@#$REL_SUPABASE#g" \
    -e "s#@@UI@@#$REL_UI#g" \
    -e "s#@@ROUTER@@#$ROUTER#g" \
    -e "s#@@AUTH@@#$REL_AUTH#g" \
    -e "s#@@VIEW@@#$REL_VIEW#g" \
    -e "s#@@EXPORT@@#$EXPORT_DECL#g" "$f"
done

# 5. Terapkan patch halaman (terakhir)
mv "$PAGE_FILE.new" "$PAGE_FILE"

echo
echo "Selesai. Berkas baru di $OUT_DIR, $PAGE_FILE diganti (tinjau dengan git diff)."
echo "Berikutnya: npx tsc --noEmit -p . && npx vitest run src/features/katalog"
