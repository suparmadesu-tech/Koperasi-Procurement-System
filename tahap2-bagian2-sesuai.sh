#!/usr/bin/env bash
# Tahap 2, Bagian 2: layar baca katalog (daftar, pencarian, filter, detail dengan foto).
# Jalankan dari akar repo setelah Bagian 1: bash tahap2-bagian2-sesuai.sh
# DISESUAIKAN: pembungkus halaman tanpa padding sendiri (Layout.tsx sudah memberi margin dan jarak menu bawah).
set -euo pipefail

OUT_DIR="src/features/katalog"
PAGE_FILE="${PAGE_FILE:-src/pages/Katalog.tsx}"
UI_FILE="${UI_FILE:-src/components/ui.ts}"
MONEY_FILE="${MONEY_FILE:-src/lib/money.ts}"
SUPABASE_FILE="${SUPABASE_FILE:-src/lib/supabase.ts}"

fail() { echo "BERHENTI, tidak ada yang diubah: $*" >&2; exit 1; }

# 1. Pemeriksaan awal (tanpa menulis apa pun)
command -v node >/dev/null || fail "node tidak ditemukan."
[ -f package.json ] || fail "jalankan dari akar repo."
for f in "$PAGE_FILE" "$UI_FILE" "$MONEY_FILE" "$SUPABASE_FILE" \
  "$OUT_DIR/useCatalog.ts" "$OUT_DIR/search.ts" "$OUT_DIR/types.ts"; do
  [ -f "$f" ] || fail "berkas $f tidak ditemukan (Bagian 1 sudah dijalankan?)."
done
has_export() { grep -Eq "export[[:space:]]+(async[[:space:]]+)?(const|function|let)[[:space:]]+$2\b" "$1"; }
has_export "$OUT_DIR/useCatalog.ts" useCatalog || fail "useCatalog tidak diekspor oleh $OUT_DIR/useCatalog.ts."
has_export "$OUT_DIR/search.ts" filterProducts || fail "filterProducts tidak diekspor oleh $OUT_DIR/search.ts."
has_export "$OUT_DIR/search.ts" indexById || fail "indexById tidak diekspor oleh $OUT_DIR/search.ts."
has_export "$OUT_DIR/search.ts" compareByName || fail "compareByName tidak diekspor oleh $OUT_DIR/search.ts."
has_export "$UI_FILE" btnSecondary || fail "$UI_FILE tidak mengekspor btnSecondary."
has_export "$UI_FILE" inputClass || fail "$UI_FILE tidak mengekspor inputClass."
has_export "$MONEY_FILE" formatRupiah || fail "$MONEY_FILE tidak mengekspor formatRupiah."
grep -Eq 'export[[:space:]]+(const|let)[[:space:]]+D\b' "$MONEY_FILE" || fail "$MONEY_FILE tidak mengekspor D."
has_export "$SUPABASE_FILE" supabase || fail "$SUPABASE_FILE tidak mengekspor supabase."

ROUTER="$(node -e "
const p=require('./package.json');const d={...p.dependencies,...p.devDependencies};
console.log(d['react-router-dom']?'react-router-dom':d['react-router']?'react-router':'')")"
[ -n "$ROUTER" ] || fail "react-router-dom atau react-router tidak ada di package.json."

AUTH_FILES="$(grep -rlE "export[[:space:]]+(const|function)[[:space:]]+useAuth\b" src || true)"
[ "$(printf '%s\n' "$AUTH_FILES" | grep -c .)" = "1" ] \
  || fail "useAuth harus diekspor tepat satu berkas di src/, ditemukan: ${AUTH_FILES:-tidak ada}."
AUTH_FILE="$AUTH_FILES"

for n in KatalogView ProductSheet photo viewModel; do
  [ ! -e "$OUT_DIR/$n.ts" ] && [ ! -e "$OUT_DIR/$n.tsx" ] || fail "$OUT_DIR/$n sudah ada; skrip tidak menimpa berkas."
done
[ ! -e "$OUT_DIR/viewModel.test.ts" ] || fail "$OUT_DIR/viewModel.test.ts sudah ada."

# Gaya argumen formatRupiah dibaca dari tanda tangannya; bila tidak jelas dipakai objek D.
SIG="$(grep -E 'export[[:space:]]+(const|function)[[:space:]]+formatRupiah' "$MONEY_FILE" | head -1)"
PARAMS="$(printf '%s' "$SIG" | sed -nE 's/^[^(]*\(([^)]*)\).*/\1/p')"
MONEY_IMPORT='{ D, formatRupiah }'
FORMAT_ARG='new D(price)'
if printf '%s' "$PARAMS" | grep -Eq 'Decimal|Value|Amount|\bD\b'; then
  :
elif printf '%s' "$PARAMS" | grep -q 'string'; then
  FORMAT_ARG='price'; MONEY_IMPORT='{ formatRupiah }'
elif printf '%s' "$PARAMS" | grep -q 'number'; then
  FORMAT_ARG='Number(price)'; MONEY_IMPORT='{ formatRupiah }'
fi

relfrom() { node -e "
const p=require('path');
let r=p.relative(process.argv[1],process.argv[2]).split(p.sep).join('/').replace(/\.tsx?$/,'');
console.log(r.startsWith('.')?r:'./'+r)" "$1" "$2"; }
REL_UI="$(relfrom "$OUT_DIR" "$UI_FILE")"
REL_MONEY="$(relfrom "$OUT_DIR" "$MONEY_FILE")"
REL_SUPABASE="$(relfrom "$OUT_DIR" "$SUPABASE_FILE")"
REL_AUTH="$(relfrom "$(dirname "$PAGE_FILE")" "$AUTH_FILE")"
REL_VIEW="$(relfrom "$(dirname "$PAGE_FILE")" "$OUT_DIR/KatalogView")"

# 2. Patch halaman Katalog: harus berupa placeholder dengan satu ekspor Katalog
PATCH_JS="$(mktemp)"
trap 'rm -f "$PATCH_JS"' EXIT
cat > "$PATCH_JS" <<'PATCH_END'
const fs = require('fs')
const file = process.argv[2]
const src = fs.readFileSync(file, 'utf8')
if (src.includes('kps:katalog-baca')) {
  console.error(file + ' sudah berisi layar katalog (penanda kps:katalog-baca).')
  process.exit(1)
}
const lines = src.split('\n').length
const kinds = [
  ['default', /export\s+default\s+function\s+Katalog\b/g],
  ['named', /export\s+function\s+Katalog\b/g],
  ['named', /export\s+const\s+Katalog\b/g],
]
const hits = kinds.flatMap(([k, re]) => [...src.matchAll(re)].map(() => k))
if (hits.length !== 1 || lines > 60) {
  console.error(
    file + ': bukan placeholder yang dikenali (ekspor Katalog cocok ' + hits.length +
      ' kali, ' + lines + ' baris; syarat: tepat 1 kali dan paling banyak 60 baris).',
  )
  process.exit(1)
}
console.log(hits[0])
PATCH_JS_END_PLACEHOLDER
PATCH_END
sed -i '/PATCH_JS_END_PLACEHOLDER/d' "$PATCH_JS"
EXPORT_KIND="$(node "$PATCH_JS" "$PAGE_FILE")" || fail "patch $PAGE_FILE ditolak (lihat pesan di atas)."
if [ "$EXPORT_KIND" = "default" ]; then EXPORT_DECL="export default function"; else EXPORT_DECL="export function"; fi

# 3. Berkas baru
cat > "$OUT_DIR/viewModel.ts" <<'TS_END'
import @@MONEY_IMPORT@@ from '@@MONEY@@'
import type { CategoryRow, ProductRow, UnitRow } from './types'

// Daftar tampil bertahap agar katalog besar tetap ringan di HP.
export const PAGE_STEP = 50

export interface ProductView {
  categoryName: string
  categoryArchived: boolean
  unitName: string
  unitArchived: boolean
  allowFraction: boolean | null
  priceText: string | null
}

export function describeProduct(
  product: ProductRow,
  categories: ReadonlyMap<string, CategoryRow>,
  units: ReadonlyMap<string, UnitRow>,
): ProductView {
  const category = categories.get(product.category_id)
  const unit = units.get(product.unit_id)
  const price = product.price
  return {
    categoryName: category?.name ?? 'Tanpa kategori',
    categoryArchived: category?.is_archived ?? false,
    unitName: unit?.name ?? 'Tanpa satuan',
    unitArchived: unit?.is_archived ?? false,
    allowFraction: unit ? unit.allow_fraction : null,
    priceText: price === null ? null : formatRupiah(@@FORMAT_ARG@@),
  }
}

export function pageSlice<T>(items: readonly T[], limit: number): { shown: T[]; remaining: number } {
  const shown = items.slice(0, Math.max(0, limit))
  return { shown, remaining: items.length - shown.length }
}

// Zona waktu tampilan Asia/Jakarta (FR-039).
export function formatClock(iso: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(iso))
}
TS_END

cat > "$OUT_DIR/viewModel.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { describeProduct, formatClock, pageSlice } from './viewModel'
import type { CategoryRow, ProductRow, UnitRow } from './types'

const base = { workspace_id: 'w', updated_at: '2026-11-18T00:00:00Z' }
const cat: CategoryRow = { ...base, id: 'c1', name: 'Sembako', is_archived: false }
const catOld: CategoryRow = { ...base, id: 'c2', name: 'Lama', is_archived: true }
const kg: UnitRow = { ...base, id: 'u1', name: 'kg', is_archived: false, allow_fraction: true }
const pcs: UnitRow = { ...base, id: 'u2', name: 'pcs', is_archived: true, allow_fraction: false }

const product = (patch: Partial<ProductRow>): ProductRow => ({
  ...base,
  id: 'p1',
  category_id: 'c1',
  unit_id: 'u1',
  name: 'Gula',
  photo_path: null,
  price: null,
  is_archived: false,
  ...patch,
})

const cats = new Map([cat, catOld].map((c) => [c.id, c]))
const units = new Map([kg, pcs].map((u) => [u.id, u]))

describe('describeProduct', () => {
  it('memuat kategori, satuan, dan harga terformat', () => {
    const v = describeProduct(product({ price: '12500' }), cats, units)
    expect(v.categoryName).toBe('Sembako')
    expect(v.unitName).toBe('kg')
    expect(v.allowFraction).toBe(true)
    expect(v.priceText).toContain('12.500')
  })
  it('harga kosong tidak menjadi nol, harga 0 tetap harga', () => {
    expect(describeProduct(product({ price: null }), cats, units).priceText).toBeNull()
    expect(describeProduct(product({ price: '0' }), cats, units).priceText).toContain('0')
  })
  it('menandai kategori dan satuan yang diarsipkan (FR-047)', () => {
    const v = describeProduct(product({ category_id: 'c2', unit_id: 'u2' }), cats, units)
    expect(v.categoryArchived).toBe(true)
    expect(v.unitArchived).toBe(true)
    expect(v.allowFraction).toBe(false)
  })
  it('rujukan yang belum ada di perangkat memakai teks cadangan', () => {
    const v = describeProduct(product({ category_id: 'x', unit_id: 'y' }), cats, units)
    expect(v.categoryName).toBe('Tanpa kategori')
    expect(v.unitName).toBe('Tanpa satuan')
    expect(v.allowFraction).toBeNull()
  })
})

describe('pageSlice', () => {
  it('memotong dan menghitung sisa', () => {
    expect(pageSlice([1, 2, 3, 4, 5], 2)).toEqual({ shown: [1, 2], remaining: 3 })
    expect(pageSlice([1, 2], 50)).toEqual({ shown: [1, 2], remaining: 0 })
    expect(pageSlice([], 50)).toEqual({ shown: [], remaining: 0 })
  })
})

describe('formatClock', () => {
  it('memakai zona waktu Asia/Jakarta', () => {
    expect(formatClock('2026-11-18T03:05:00Z')).toMatch(/10[.:]05/)
  })
})
TS_END

cat > "$OUT_DIR/photo.ts" <<'TS_END'
import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@@SUPABASE@@'

const BUCKET = 'kps-photos'
const TTL_SECONDS = 3600
const REFRESH_MARGIN_MS = 60_000

const cache = new Map<string, { url: string; expiresAt: number }>()

function peek(path: string): string | null {
  const hit = cache.get(path)
  return hit && hit.expiresAt - Date.now() > REFRESH_MARGIN_MS ? hit.url : null
}

// Bucket privat: setiap tampilan memakai URL bertanda tangan berumur 1 jam.
export async function getSignedPhotoUrl(path: string): Promise<string> {
  const cached = peek(path)
  if (cached) return cached
  if (!supabase) throw new Error('Supabase belum dikonfigurasi.')
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, TTL_SECONDS)
  if (error || !data) throw error ?? new Error('URL foto tidak tersedia.')
  cache.set(path, { url: data.signedUrl, expiresAt: Date.now() + TTL_SECONDS * 1000 })
  return data.signedUrl
}

// Dipanggil saat keluar agar URL akun lama tidak tersisa di memori.
export function clearPhotoUrlCache() {
  cache.clear()
}

export type PhotoState =
  | { kind: 'none' }
  | { kind: 'loading' }
  | { kind: 'ready'; url: string }
  | { kind: 'offline' }
  | { kind: 'error' }

export function usePhotoUrl(path: string | null) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState<PhotoState>({ kind: path ? 'loading' : 'none' })

  useEffect(() => {
    if (!path) {
      setState({ kind: 'none' })
      return undefined
    }
    const cached = peek(path)
    if (cached) {
      setState({ kind: 'ready', url: cached })
      return undefined
    }
    let cancelled = false
    setState({ kind: 'loading' })
    getSignedPhotoUrl(path)
      .then((url) => {
        if (!cancelled) setState({ kind: 'ready', url })
      })
      .catch(() => {
        if (!cancelled) setState({ kind: navigator.onLine ? 'error' : 'offline' })
      })
    return () => {
      cancelled = true
    }
  }, [path, attempt])

  useEffect(() => {
    const retryOnline = () => setAttempt((n) => n + 1)
    window.addEventListener('online', retryOnline)
    return () => window.removeEventListener('online', retryOnline)
  }, [])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  // Gambar gagal dimuat biasanya karena URL kedaluwarsa atau offline.
  const reportImageError = useCallback(() => {
    if (path) cache.delete(path)
    setState({ kind: navigator.onLine ? 'error' : 'offline' })
  }, [path])

  return { state, retry, reportImageError }
}
TS_END

cat > "$OUT_DIR/ProductSheet.tsx" <<'TSX_END'
import { useEffect, useId, useRef, type KeyboardEvent } from 'react'
import { btnSecondary } from '@@UI@@'
import { usePhotoUrl } from './photo'
import type { ProductRow } from './types'
import type { ProductView } from './viewModel'

const FOCUSABLE = 'button, [href], select, input, [tabindex]:not([tabindex="-1"])'

function PhotoBox({ photoPath, name }: { photoPath: string | null; name: string }) {
  const { state, retry, reportImageError } = usePhotoUrl(photoPath)
  const note =
    state.kind === 'none'
      ? 'Belum ada foto.'
      : state.kind === 'loading'
        ? 'Memuat foto...'
        : state.kind === 'offline'
          ? 'Foto tidak tersedia saat offline.'
          : state.kind === 'error'
            ? 'Foto gagal dimuat.'
            : null

  return (
    <div className="flex aspect-[4/3] w-full items-center justify-center bg-slate-100">
      {state.kind === 'ready' ? (
        <img
          src={state.url}
          alt={name}
          width={1600}
          height={1200}
          decoding="async"
          onError={reportImageError}
          className="h-full w-full object-contain"
        />
      ) : (
        <div className="flex flex-col items-center gap-3 px-4 text-center">
          <p role="status" className="text-sm text-slate-700">
            {note}
          </p>
          {(state.kind === 'offline' || state.kind === 'error') && (
            <button type="button" onClick={retry} className={btnSecondary}>
              Coba lagi
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export function ProductSheet({
  product,
  view,
  onClose,
}: {
  product: ProductRow
  view: ProductView
  onClose: () => void
}) {
  const titleId = useId()
  const panelRef = useRef<HTMLDivElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    closeRef.current?.focus()
    return () => {
      document.body.style.overflow = previousOverflow
      opener?.focus()
    }
  }, [])

  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    if (e.key === 'Escape') {
      e.stopPropagation()
      onClose()
      return
    }
    if (e.key !== 'Tab') return
    const nodes = panelRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE)
    if (!nodes || nodes.length === 0) return
    const first = nodes[0]
    const last = nodes[nodes.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault()
      first.focus()
    }
  }

  const fraction =
    view.allowFraction === null
      ? 'Belum diketahui'
      : view.allowFraction
        ? 'Boleh pecahan'
        : 'Hanya bilangan bulat'

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-black/50 sm:items-center sm:p-6"
      onKeyDown={onKeyDown}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className="max-h-[90dvh] w-full max-w-md overflow-y-auto rounded-t-xl bg-white pb-[max(1rem,env(safe-area-inset-bottom))] sm:rounded-lg sm:pb-4"
      >
        <PhotoBox photoPath={product.photo_path} name={product.name} />
        <div className="px-4 pt-4">
          <div className="flex items-start justify-between gap-3">
            <h2 id={titleId} className="break-words text-lg font-semibold text-slate-900">
              {product.name}
            </h2>
            {product.is_archived && (
              <span className="mt-1 shrink-0 rounded-sm border border-slate-500 px-1.5 text-xs text-slate-800">
                Diarsipkan
              </span>
            )}
          </div>

          <dl className="mt-4 grid grid-cols-[7rem_1fr] gap-x-3 gap-y-2 text-sm">
            <dt className="text-slate-600">Harga</dt>
            <dd className="tabular-nums text-slate-900">{view.priceText ?? 'Harga belum tersedia'}</dd>
            <dt className="text-slate-600">Kategori</dt>
            <dd className="break-words text-slate-900">
              {view.categoryName}
              {view.categoryArchived && ' (Diarsipkan)'}
            </dd>
            <dt className="text-slate-600">Satuan</dt>
            <dd className="break-words text-slate-900">
              {view.unitName}
              {view.unitArchived && ' (Diarsipkan)'}
            </dd>
            <dt className="text-slate-600">Jumlah</dt>
            <dd className="text-slate-900">{fraction}</dd>
          </dl>

          <button ref={closeRef} type="button" onClick={onClose} className={`${btnSecondary} mt-6 w-full`}>
            Tutup
          </button>
        </div>
      </div>
    </div>
  )
}
TSX_END

cat > "$OUT_DIR/KatalogView.tsx" <<'TSX_END'
import { useDeferredValue, useEffect, useId, useMemo, useState } from 'react'
import { Link } from '@@ROUTER@@'
import { btnSecondary, inputClass } from '@@UI@@'
import { ProductSheet } from './ProductSheet'
import { compareByName, filterProducts, indexById, type ArchiveFilter } from './search'
import { useCatalog } from './useCatalog'
import { describeProduct, formatClock, pageSlice, PAGE_STEP } from './viewModel'

const labelClass = 'mb-1 block text-sm font-medium text-slate-800'
const rowFocus = 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-slate-900'

export function KatalogView({ workspaceId, isAdmin }: { workspaceId: string; isAdmin: boolean }) {
  const { data, loading, readError, sync, refresh } = useCatalog(workspaceId)
  const [query, setQuery] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [archive, setArchive] = useState<ArchiveFilter>('active')
  const [limit, setLimit] = useState(PAGE_STEP)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const deferredQuery = useDeferredValue(query)
  const queryId = useId()
  const categoryFieldId = useId()
  const archiveId = useId()

  const categories = useMemo(() => indexById(data?.categories ?? []), [data])
  const units = useMemo(() => indexById(data?.units ?? []), [data])
  const categoryOptions = useMemo(
    () => [...(data?.categories ?? [])].sort(compareByName),
    [data],
  )
  const filtered = useMemo(
    () =>
      filterProducts(data?.products ?? [], {
        query: deferredQuery,
        categoryId: categoryId || null,
        archive,
      }),
    [data, deferredQuery, categoryId, archive],
  )
  const { shown, remaining } = pageSlice(filtered, limit)
  const selected = selectedId ? (data?.products.find((p) => p.id === selectedId) ?? null) : null

  useEffect(() => {
    setLimit(PAGE_STEP)
  }, [deferredQuery, categoryId, archive])

  const hasFilter = query !== '' || categoryId !== '' || archive !== 'active'
  const resetFilters = () => {
    setQuery('')
    setCategoryId('')
    setArchive('active')
  }

  const total = data?.products.length ?? 0

  return (
    <div className="w-full">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-slate-900">Katalog</h1>
        {isAdmin && (
          <Link to="/pengaturan/admin" className={btnSecondary}>
            Kelola katalog
          </Link>
        )}
      </div>

      <SyncLine state={sync} onRetry={refresh} />

      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)]">
        <div className="col-span-2 sm:col-span-1">
          <label htmlFor={queryId} className={labelClass}>
            Cari barang
          </label>
          <input
            id={queryId}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoComplete="off"
            className={inputClass}
          />
        </div>
        <div>
          <label htmlFor={categoryFieldId} className={labelClass}>
            Kategori
          </label>
          <select
            id={categoryFieldId}
            value={categoryId}
            onChange={(e) => setCategoryId(e.target.value)}
            className={inputClass}
          >
            <option value="">Semua</option>
            {categoryOptions.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
                {c.is_archived ? ' (Diarsipkan)' : ''}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={archiveId} className={labelClass}>
            Status
          </label>
          <select
            id={archiveId}
            value={archive}
            onChange={(e) => setArchive(e.target.value as ArchiveFilter)}
            className={inputClass}
          >
            <option value="active">Aktif</option>
            <option value="archived">Diarsipkan</option>
            <option value="all">Semua</option>
          </select>
        </div>
      </div>

      <div className="mt-6">
        {readError ? (
          <p role="alert" className="text-sm text-red-800">
            Katalog di perangkat tidak dapat dibaca: {readError}
          </p>
        ) : loading ? (
          <p role="status" className="text-sm text-slate-700">
            Memuat katalog dari perangkat...
          </p>
        ) : total === 0 ? (
          <EmptyCatalog status={sync.status} isAdmin={isAdmin} />
        ) : filtered.length === 0 ? (
          <div className="rounded-md border border-slate-300 p-4">
            <p className="text-sm text-slate-900">Tidak ada barang yang cocok dengan pencarian ini.</p>
            {hasFilter && (
              <button type="button" onClick={resetFilters} className={`${btnSecondary} mt-3`}>
                Atur ulang pencarian
              </button>
            )}
          </div>
        ) : (
          <>
            <p aria-live="polite" className="mb-2 text-sm text-slate-700">
              {filtered.length} barang
            </p>
            <ul className="divide-y divide-slate-200 border-y border-slate-200 bg-white">
              {shown.map((p) => {
                const v = describeProduct(p, categories, units)
                return (
                  <li key={p.id}>
                    <button
                      type="button"
                      onClick={() => setSelectedId(p.id)}
                      className={`flex min-h-14 w-full items-start justify-between gap-3 px-4 py-3 text-left hover:bg-slate-50 ${rowFocus}`}
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
              <button
                type="button"
                onClick={() => setLimit((n) => n + PAGE_STEP)}
                className={`${btnSecondary} mt-4 w-full`}
              >
                Tampilkan {Math.min(PAGE_STEP, remaining)} lagi (sisa {remaining})
              </button>
            )}
          </>
        )}
      </div>

      {selected && (
        <ProductSheet
          product={selected}
          view={describeProduct(selected, categories, units)}
          onClose={() => setSelectedId(null)}
        />
      )}
    </div>
  )
}

function SyncLine({
  state,
  onRetry,
}: {
  state: ReturnType<typeof useCatalog>['sync']
  onRetry: () => void
}) {
  if (state.status === 'error') {
    return (
      <div role="alert" className="mt-2 flex flex-wrap items-center gap-3 text-sm text-red-800">
        <span>Gagal menyegarkan katalog: {state.error}</span>
        <button type="button" onClick={onRetry} className={btnSecondary}>
          Coba lagi
        </button>
      </div>
    )
  }
  const text =
    state.status === 'offline'
      ? 'Offline. Menampilkan data yang tersimpan di perangkat.'
      : state.status === 'syncing'
        ? 'Menyegarkan dari server...'
        : state.status === 'ok' && state.lastSyncedAt
          ? `Diperbarui pukul ${formatClock(state.lastSyncedAt)}.`
          : ''
  return (
    <p role="status" className="mt-2 min-h-5 text-sm text-slate-700">
      {text}
    </p>
  )
}

function EmptyCatalog({ status, isAdmin }: { status: string; isAdmin: boolean }) {
  if (status === 'idle' || status === 'syncing') {
    return (
      <p role="status" className="text-sm text-slate-700">
        Mengambil katalog dari server...
      </p>
    )
  }
  if (status === 'offline') {
    return (
      <p className="text-sm text-slate-900">
        Belum ada data katalog di perangkat. Sambungkan ke internet untuk mengambilnya.
      </p>
    )
  }
  if (status === 'error') {
    return <p className="text-sm text-slate-900">Katalog belum dapat diambil dari server.</p>
  }
  return (
    <div className="rounded-md border border-slate-300 p-4 text-sm text-slate-900">
      {isAdmin ? (
        <>
          <p>Katalog masih kosong.</p>
          <Link to="/pengaturan/admin" className={`${btnSecondary} mt-3 inline-block`}>
            Tambah barang
          </Link>
        </>
      ) : (
        <p>Katalog masih kosong. Admin belum menambahkan barang.</p>
      )}
    </div>
  )
}
TSX_END

cat > "$PAGE_FILE.new" <<'TSX_END'
// kps:katalog-baca
import { useAuth } from '@@AUTH@@'
import { KatalogView } from '@@VIEW@@'

@@EXPORT@@ Katalog() {
  const { state } = useAuth()
  if (state.status !== 'ready') return null
  return <KatalogView workspaceId={state.workspace.id} isAdmin={state.role === 'admin'} />
}
TSX_END

# 4. Isi jalur relatif
for f in "$OUT_DIR/viewModel.ts" "$OUT_DIR/photo.ts" "$OUT_DIR/ProductSheet.tsx" "$OUT_DIR/KatalogView.tsx" "$PAGE_FILE.new"; do
  sed -i \
    -e "s#@@MONEY_IMPORT@@#$MONEY_IMPORT#g" \
    -e "s#@@MONEY@@#$REL_MONEY#g" \
    -e "s#@@SUPABASE@@#$REL_SUPABASE#g" \
    -e "s#@@UI@@#$REL_UI#g" \
    -e "s#@@ROUTER@@#$ROUTER#g" \
    -e "s#@@AUTH@@#$REL_AUTH#g" \
    -e "s#@@VIEW@@#$REL_VIEW#g" \
    -e "s#@@EXPORT@@#$EXPORT_DECL#g" \
    -e "s#@@FORMAT_ARG@@#$FORMAT_ARG#g" "$f"
done

# 5. Terapkan patch halaman (terakhir)
mv "$PAGE_FILE.new" "$PAGE_FILE"

echo
echo "Selesai. Berkas baru di $OUT_DIR, $PAGE_FILE diganti (tinjau dengan git diff)."
echo "Berikutnya: npx tsc --noEmit -p . && npx vitest run src/features/katalog"
