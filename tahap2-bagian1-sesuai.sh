#!/usr/bin/env bash
# Tahap 2, Bagian 1: lapisan data katalog (Dexie v2, penyegaran, Realtime, validasi, penulisan).
# Jalankan dari akar repo: bash tahap2-bagian1.sh
# DISESUAIKAN dengan repo nyata: db.ts mengekspor getDb(), money.ts mengekspor D.
# Variabel jalur (ASUMSI) dapat diganti: DB_FILE=... MONEY_FILE=... SUPABASE_FILE=... bash tahap2-bagian1.sh
set -euo pipefail

DB_FILE="${DB_FILE:-src/lib/db.ts}"
MONEY_FILE="${MONEY_FILE:-src/lib/money.ts}"
SUPABASE_FILE="${SUPABASE_FILE:-src/lib/supabase.ts}"
OUT_DIR="src/features/katalog"

fail() { echo "BERHENTI, tidak ada yang diubah: $*" >&2; exit 1; }

# 1. Pemeriksaan awal (tanpa menulis apa pun)
[ -f package.json ] || fail "jalankan dari akar repo (package.json tidak ada)."
for f in "$DB_FILE" "$MONEY_FILE" "$SUPABASE_FILE"; do
  [ -f "$f" ] || fail "berkas $f tidak ditemukan. Atur lewat variabel DB_FILE, MONEY_FILE, SUPABASE_FILE."
done
grep -Eq 'export[[:space:]]+function[[:space:]]+getDb\b' "$DB_FILE" \
  || fail "$DB_FILE tidak mengekspor getDb()."
grep -Eq 'export[[:space:]]+(const|let)[[:space:]]+supabase\b' "$SUPABASE_FILE" \
  || fail "$SUPABASE_FILE tidak mengekspor 'supabase'."
grep -Eq 'export[[:space:]]+const[[:space:]]+D\b' "$MONEY_FILE" \
  || fail "$MONEY_FILE tidak mengekspor 'D' (konstruktor Decimal)."
for n in types moneyAdapter validation search errors rows catalogStore catalogSync catalogWrite useCatalog; do
  [ ! -e "$OUT_DIR/$n.ts" ] || fail "$OUT_DIR/$n.ts sudah ada; skrip tidak menimpa berkas."
done
for n in validation search errors rows; do
  [ ! -e "$OUT_DIR/$n.test.ts" ] || fail "$OUT_DIR/$n.test.ts sudah ada; skrip tidak menimpa berkas."
done
command -v node >/dev/null || fail "node tidak ditemukan."

rel() { node -e "
const p=require('path');
let r=p.relative(process.argv[1],process.argv[2]).split(p.sep).join('/').replace(/\.tsx?$/,'');
console.log(r.startsWith('.')?r:'./'+r)" "$OUT_DIR" "$1"; }
REL_DB="$(rel "$DB_FILE")"
REL_MONEY="$(rel "$MONEY_FILE")"
REL_SUPABASE="$(rel "$SUPABASE_FILE")"

# 2. Patch db.ts: dicek dulu, ditulis paling akhir
PATCH_JS="$(mktemp)"
trap 'rm -f "$PATCH_JS"' EXIT
cat > "$PATCH_JS" <<'PATCH_END'
const fs = require('fs')
const path = require('path')
const [, , mode, file, typesImport] = process.argv
const src = fs.readFileSync(file, 'utf8')
const MARK = 'kps:katalog-v2'

if (src.includes(MARK)) {
  console.log(file + ' sudah berisi patch katalog; dilewati.')
  process.exit(0)
}
const classRe = /^(export\s+)?class\s+\w+\s+extends\s+Dexie\s*\{/gm
const verRe = /this\.version\(1\)\.stores\(\{[\s\S]*?\}\)/g
const classHits = [...src.matchAll(classRe)]
const verHits = [...src.matchAll(verRe)]
const verCalls = (src.match(/this\.version\(/g) || []).length
if (classHits.length !== 1 || verHits.length !== 1 || verCalls !== 1) {
  console.error(
    file + ': pola tidak cocok tepat satu kali (kelas Dexie: ' + classHits.length +
      ', version(1).stores: ' + verHits.length + ', semua version(): ' + verCalls + ').',
  )
  process.exit(1)
}
const v = verHits[0]
const c = classHits[0]
if (c.index > v.index) {
  console.error(file + ': urutan kelas dan version(1) tidak seperti yang diasumsikan.')
  process.exit(1)
}
const T = (name) => `import('${typesImport}').${name}`
const fields =
  `\n  // ${MARK}: tabel katalog, tabel ops tidak berubah\n` +
  `  declare categories: import('dexie').Table<${T('CategoryRow')}, string>\n` +
  `  declare units: import('dexie').Table<${T('UnitRow')}, string>\n` +
  `  declare products: import('dexie').Table<${T('ProductRow')}, string>\n`
const upgrade =
  `\n    this.version(2).stores({\n` +
  `      categories: 'id, workspace_id, name',\n` +
  `      units: 'id, workspace_id, name',\n` +
  `      products: 'id, workspace_id, category_id, unit_id, name',\n` +
  `    })`
const vEnd = v.index + v[0].length
const cEnd = c.index + c[0].length
const out = src.slice(0, cEnd) + fields + src.slice(cEnd, vEnd) + upgrade + src.slice(vEnd)
if (mode === 'apply') fs.writeFileSync(file, out)
console.log(file + (mode === 'apply' ? ': patch diterapkan.' : ': pola cocok, siap dipatch.'))
PATCH_END
TYPES_FROM_DB="$(node -e "
const p=require('path');
let r=p.relative(p.dirname(process.argv[1]),process.argv[2]).split(p.sep).join('/');
console.log(r.startsWith('.')?r:'./'+r)" "$DB_FILE" "$OUT_DIR/types")"
node "$PATCH_JS" check "$DB_FILE" "$TYPES_FROM_DB" || fail "patch $DB_FILE ditolak (lihat pesan di atas)."

mkdir -p "$OUT_DIR"

# 3. Berkas baru
cat > "$OUT_DIR/types.ts" <<'TS_END'
export interface CategoryRow {
  id: string
  workspace_id: string
  name: string
  is_archived: boolean
  updated_at: string
}

export interface UnitRow extends CategoryRow {
  allow_fraction: boolean
}

export interface ProductRow {
  id: string
  workspace_id: string
  category_id: string
  unit_id: string
  name: string
  photo_path: string | null
  // Rupiah bulat sebagai string desimal; tidak pernah float (FR-038).
  price: string | null
  is_archived: boolean
  updated_at: string
}

export interface CatalogData {
  categories: CategoryRow[]
  units: UnitRow[]
  products: ProductRow[]
}

export interface CatalogError {
  code: string
  message: string
}

export type Result<T> = { ok: true; data: T } | { ok: false; error: CatalogError }

// Batas BR-039. Satuan katalog 50 karena disalin ke unit_snapshot.
export const TEXT_LIMITS = { categoryName: 200, unitName: 50, productName: 200 } as const
TS_END

cat > "$OUT_DIR/moneyAdapter.ts" <<'TS_END'
import { D } from '@@MONEY@@'

// Batas kolom kps_rupiah di database.
export const MAX_RUPIAH = '99999999999999'

export type PriceParse = { ok: true; value: string | null } | { ok: false; message: string }

const PLAIN = /^\d+$/
const GROUPED = /^\d{1,3}(\.\d{3})+$/

// Menerima "12500", "12.500", "Rp 12.500", "12.500,00". Kosong berarti harga belum ada.
export function parsePriceInput(raw: string): PriceParse {
  let text = raw.trim().replace(/^rp\.?\s*/i, '').replace(/\s+/g, '')
  if (text === '') return { ok: true, value: null }
  if (text.startsWith('-')) return { ok: false, message: 'Harga tidak boleh negatif.' }

  const comma = text.indexOf(',')
  if (comma !== -1) {
    if (!/^0*$/.test(text.slice(comma + 1))) {
      return { ok: false, message: 'Harga harus Rupiah bulat, tanpa pecahan.' }
    }
    text = text.slice(0, comma)
  }
  if (!PLAIN.test(text) && !GROUPED.test(text)) {
    return { ok: false, message: 'Harga hanya boleh berisi angka, contoh 12500 atau 12.500.' }
  }
  const value = new D(text.replace(/\./g, ''))
  if (!value.lte(MAX_RUPIAH)) return { ok: false, message: 'Harga terlalu besar.' }
  return { ok: true, value: value.toFixed(0) }
}
TS_END

cat > "$OUT_DIR/validation.ts" <<'TS_END'
import { parsePriceInput } from './moneyAdapter'
import { TEXT_LIMITS } from './types'

export type FormResult<V, K extends string> =
  | { ok: true; value: V }
  | { ok: false; errors: Partial<Record<K, string>> }

// Panjang dihitung per code point, sama dengan char_length di PostgreSQL.
const charCount = (s: string) => Array.from(s).length

function checkName(raw: string, max: number, label: string): { value: string } | { error: string } {
  const value = raw.trim()
  if (value === '') return { error: `${label} wajib diisi.` }
  if (charCount(value) > max) return { error: `${label} maksimal ${max} karakter.` }
  return { value }
}

export function validateCategoryForm(input: { name: string }): FormResult<{ name: string }, 'name'> {
  const n = checkName(input.name, TEXT_LIMITS.categoryName, 'Nama kategori')
  if ('error' in n) return { ok: false, errors: { name: n.error } }
  return { ok: true, value: { name: n.value } }
}

export function validateUnitForm(input: {
  name: string
  allowFraction: boolean
}): FormResult<{ name: string; allow_fraction: boolean }, 'name'> {
  const n = checkName(input.name, TEXT_LIMITS.unitName, 'Nama satuan')
  if ('error' in n) return { ok: false, errors: { name: n.error } }
  return { ok: true, value: { name: n.value, allow_fraction: input.allowFraction } }
}

export interface ProductFormValue {
  name: string
  categoryId: string
  unitId: string
  price: string | null
}

export function validateProductForm(input: {
  name: string
  categoryId: string
  unitId: string
  priceText: string
}): FormResult<ProductFormValue, 'name' | 'categoryId' | 'unitId' | 'price'> {
  const errors: Partial<Record<'name' | 'categoryId' | 'unitId' | 'price', string>> = {}

  const n = checkName(input.name, TEXT_LIMITS.productName, 'Nama barang')
  if ('error' in n) errors.name = n.error
  if (!input.categoryId) errors.categoryId = 'Pilih kategori.'
  if (!input.unitId) errors.unitId = 'Pilih satuan.'
  const p = parsePriceInput(input.priceText)
  if (!p.ok) errors.price = p.message

  if ('error' in n || !p.ok || errors.categoryId || errors.unitId) return { ok: false, errors }
  return {
    ok: true,
    value: { name: n.value, categoryId: input.categoryId, unitId: input.unitId, price: p.value },
  }
}
TS_END

cat > "$OUT_DIR/search.ts" <<'TS_END'
import type { ProductRow } from './types'

export type ArchiveFilter = 'active' | 'archived' | 'all'

export interface CatalogFilter {
  query?: string
  categoryId?: string | null
  archive?: ArchiveFilter
}

export function normalizeText(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim()
}

const collator = new Intl.Collator('id', { sensitivity: 'base', numeric: true })

export const compareByName = (a: { name: string; id: string }, b: { name: string; id: string }) =>
  collator.compare(a.name, b.name) || a.id.localeCompare(b.id)

// Semua kata pada query harus ada di nama (FR-007). Hasil diurutkan menurut nama.
export function filterProducts(products: readonly ProductRow[], filter: CatalogFilter = {}): ProductRow[] {
  const tokens = normalizeText(filter.query ?? '').split(' ').filter(Boolean)
  const archive = filter.archive ?? 'all'
  const out = products.filter((p) => {
    if (archive === 'active' && p.is_archived) return false
    if (archive === 'archived' && !p.is_archived) return false
    if (filter.categoryId && p.category_id !== filter.categoryId) return false
    if (tokens.length === 0) return true
    const name = normalizeText(p.name)
    return tokens.every((t) => name.includes(t))
  })
  return out.sort(compareByName)
}

// Pilihan untuk form: hanya yang aktif, ditambah nilai yang sedang dipakai walau diarsipkan (FR-047).
export function selectableOptions<T extends { id: string; name: string; is_archived: boolean }>(
  rows: readonly T[],
  currentId?: string | null,
): T[] {
  return rows.filter((r) => !r.is_archived || r.id === currentId).sort(compareByName)
}

export function indexById<T extends { id: string }>(rows: readonly T[]): Map<string, T> {
  return new Map(rows.map((r) => [r.id, r]))
}
TS_END

cat > "$OUT_DIR/errors.ts" <<'TS_END'
import type { CatalogError } from './types'

export interface RawWriteError {
  code?: string
  message?: string
  details?: string
}

const MESSAGES: Record<string, string> = {
  OFFLINE: 'Mengubah katalog memerlukan koneksi internet. Sambungkan perangkat, lalu coba lagi.',
  AUTH_EXPIRED: 'Sesi login berakhir. Masuk kembali, lalu coba lagi.',
  KPS_FORBIDDEN: 'Anda tidak berhak melakukan perubahan ini.',
  KPS_CONFLICT: 'Data yang sama sudah ada.',
  KPS_REFERENCE_INVALID: 'Data yang dirujuk tidak ditemukan.',
  KPS_REF_ARCHIVED: 'Kategori atau satuan yang dipilih sudah diarsipkan.',
  KPS_INVALID_PRICE: 'Harga harus Rupiah bulat dan tidak negatif.',
  KPS_TEXT_TOO_LONG: 'Teks melebihi batas panjang yang diizinkan.',
  KPS_INVALID_PHOTO_PATH: 'Alamat foto tidak sesuai format.',
  KPS_INVALID_INPUT: 'Isian tidak valid.',
  KPS_CHECK_VIOLATION: 'Isian melanggar aturan data.',
  UNKNOWN: 'Perubahan gagal disimpan. Coba lagi beberapa saat.',
}

const NETWORK = /failed to fetch|networkerror|load failed|network request failed/i

const err = (code: string, message?: string): CatalogError => ({ code, message: message ?? MESSAGES[code] ?? MESSAGES.UNKNOWN })

// Pemetaan SQLSTATE dan nama constraint untuk penulisan langsung (Bagian 3, 7.2 dan 8).
export function mapWriteError(e: RawWriteError | null | undefined): CatalogError {
  const code = e?.code ?? ''
  const text = `${e?.message ?? ''} ${e?.details ?? ''}`

  if (!code && NETWORK.test(text)) return err('OFFLINE')
  if (code === 'PGRST301' || /jwt expired/i.test(text)) return err('AUTH_EXPIRED')

  const kps = /\bKPS_[A-Z_]+\b/.exec(e?.message ?? '')
  if (kps) return err(kps[0])

  if (code === '42501') return err('KPS_FORBIDDEN')
  if (code === '23503') return err('KPS_REFERENCE_INVALID')
  if (code === '23505') {
    if (/categories_name_active_uq/.test(text)) return err('KPS_CONFLICT', 'Nama kategori sudah dipakai kategori lain yang aktif.')
    if (/units_name_active_uq/.test(text)) return err('KPS_CONFLICT', 'Nama satuan sudah dipakai satuan lain yang aktif.')
    return err('KPS_CONFLICT')
  }
  if (code === '23514') {
    if (/kps_rupiah_check/.test(text)) return err('KPS_INVALID_PRICE')
    if (/(products|categories|units)_name_len_chk/.test(text)) return err('KPS_TEXT_TOO_LONG')
    if (/products_photo_path_fmt_chk/.test(text)) return err('KPS_INVALID_PHOTO_PATH')
    return err('KPS_CHECK_VIOLATION')
  }
  if (code.startsWith('22')) return err('KPS_INVALID_INPUT')
  return err('UNKNOWN')
}
TS_END

cat > "$OUT_DIR/rows.ts" <<'TS_END'
import type { ProductRow } from './types'

export interface ServerProduct extends Omit<ProductRow, 'price'> {
  price: number | string | null
}

// PostgREST mengirim numeric sebagai angka JSON; disimpan lokal sebagai string.
export function toProductRow(r: ServerProduct): ProductRow {
  return { ...r, price: r.price == null ? null : String(r.price) }
}

export interface ProductPatch {
  name?: string
  categoryId?: string
  unitId?: string
  price?: string | null
  photoPath?: string
  isArchived?: boolean
}

// Harga Rupiah bulat di bawah 1e14 aman sebagai Number saat dikirim ke server.
export const priceToWire = (price: string | null): number | null => (price === null ? null : Number(price))

export function productPatchToColumns(p: ProductPatch): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  if (p.name !== undefined) out.name = p.name
  if (p.categoryId !== undefined) out.category_id = p.categoryId
  if (p.unitId !== undefined) out.unit_id = p.unitId
  if (p.price !== undefined) out.price = priceToWire(p.price)
  if (p.photoPath !== undefined) out.photo_path = p.photoPath
  if (p.isArchived !== undefined) out.is_archived = p.isArchived
  return out
}
TS_END

cat > "$OUT_DIR/catalogStore.ts" <<'TS_END'
import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '@@DB@@'
import { supabase } from '@@SUPABASE@@'
import { toProductRow, type ServerProduct } from './rows'
import type { CatalogData, CategoryRow, UnitRow } from './types'

const sb = supabase as unknown as SupabaseClient

export const CATEGORY_COLUMNS = 'id, workspace_id, name, is_archived, updated_at'
export const UNIT_COLUMNS = 'id, workspace_id, name, allow_fraction, is_archived, updated_at'
export const PRODUCT_COLUMNS =
  'id, workspace_id, category_id, unit_id, name, photo_path, price, is_archived, updated_at'

// Batas baris per permintaan di Supabase adalah 1000 secara bawaan.
const PAGE_SIZE = 1000

export const isOnline = () => typeof navigator === 'undefined' || navigator.onLine

export function describeError(e: unknown): string {
  if (e instanceof Error) return e.message
  if (e && typeof e === 'object' && 'message' in e) return String((e as { message: unknown }).message)
  return String(e)
}

async function fetchAll<T>(table: string, columns: string, workspaceId: string): Promise<T[]> {
  const rows: T[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from(table)
      .select(columns)
      .eq('workspace_id', workspaceId)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as T[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Server tidak pernah menghapus baris katalog, jadi cukup bulkPut tanpa menghapus yang lokal.
export async function refreshCatalog(workspaceId: string): Promise<void> {
  const [categories, units, rawProducts] = await Promise.all([
    fetchAll<CategoryRow>('categories', CATEGORY_COLUMNS, workspaceId),
    fetchAll<UnitRow>('units', UNIT_COLUMNS, workspaceId),
    fetchAll<ServerProduct>('products', PRODUCT_COLUMNS, workspaceId),
  ])
  const products = rawProducts.map(toProductRow)
  const db = getDb()
  await db.transaction('rw', db.categories, db.units, db.products, async () => {
    await db.categories.bulkPut(categories)
    await db.units.bulkPut(units)
    await db.products.bulkPut(products)
  })
}

export const catalogQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<CatalogData> => {
    const db = getDb()
    return {
      categories: await db.categories.where('workspace_id').equals(workspaceId).toArray(),
      units: await db.units.where('workspace_id').equals(workspaceId).toArray(),
      products: await db.products.where('workspace_id').equals(workspaceId).toArray(),
    }
  })

// Dipakai saat keluar (FR-002). Tabel ops sengaja tidak disentuh di sini.
export async function clearCatalogLocal(): Promise<void> {
  const db = getDb()
  await db.transaction('rw', db.categories, db.units, db.products, async () => {
    await Promise.all([db.categories.clear(), db.units.clear(), db.products.clear()])
  })
}
TS_END

cat > "$OUT_DIR/catalogSync.ts" <<'TS_END'
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '@@SUPABASE@@'
import { describeError, isOnline, refreshCatalog } from './catalogStore'

const sb = supabase as unknown as SupabaseClient

export type SyncStatus = 'idle' | 'syncing' | 'ok' | 'offline' | 'error'
export interface SyncState {
  status: SyncStatus
  lastSyncedAt: string | null
  error: string | null
}

const TABLES = ['categories', 'units', 'products'] as const
// Impor besar memicu banyak event; digabung jadi satu penyegaran.
const DEBOUNCE_MS = 1500

let state: SyncState = { status: 'idle', lastSyncedAt: null, error: null }
const listeners = new Set<() => void>()
let activeWorkspace: string | null = null
let holders = 0
let channel: RealtimeChannel | null = null
let timer: ReturnType<typeof setTimeout> | undefined
let running = false
let rerun = false

function setState(patch: Partial<SyncState>) {
  state = { ...state, ...patch }
  listeners.forEach((l) => l())
}

export const getSyncState = (): SyncState => state

export function subscribeSyncState(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

async function run() {
  const workspaceId = activeWorkspace
  if (!workspaceId) return
  if (running) {
    rerun = true
    return
  }
  if (!isOnline()) {
    setState({ status: 'offline' })
    return
  }
  running = true
  setState({ status: 'syncing', error: null })
  try {
    await refreshCatalog(workspaceId)
    setState({ status: 'ok', lastSyncedAt: new Date().toISOString() })
  } catch (e) {
    setState({ status: isOnline() ? 'error' : 'offline', error: describeError(e) })
  } finally {
    running = false
    if (rerun) {
      rerun = false
      schedule(0)
    }
  }
}

function schedule(delay: number = DEBOUNCE_MS) {
  clearTimeout(timer)
  timer = setTimeout(() => {
    void run()
  }, delay)
}

const onOnline = () => schedule(0)
const onVisible = () => {
  if (document.visibilityState === 'visible') schedule(0)
}

function start(workspaceId: string) {
  activeWorkspace = workspaceId
  let ch = sb.channel(`kps-catalog-${workspaceId}`)
  for (const table of TABLES) {
    ch = ch.on(
      'postgres_changes',
      { event: '*', schema: 'public', table, filter: `workspace_id=eq.${workspaceId}` },
      () => schedule(),
    )
  }
  // Setelah tersambung ulang, ambil ulang agar event yang terlewat tidak hilang.
  channel = ch.subscribe((status) => {
    if (status === 'SUBSCRIBED') schedule(0)
  })
  window.addEventListener('online', onOnline)
  document.addEventListener('visibilitychange', onVisible)
  schedule(0)
}

function stop() {
  clearTimeout(timer)
  window.removeEventListener('online', onOnline)
  document.removeEventListener('visibilitychange', onVisible)
  if (channel) void sb.removeChannel(channel)
  channel = null
  activeWorkspace = null
  setState({ status: 'idle' })
}

// Satu langganan Realtime dipakai bersama; komponen yang memanggilnya menghitung referensi.
export function acquireCatalogSync(workspaceId: string): () => void {
  if (activeWorkspace !== null && activeWorkspace !== workspaceId) {
    stop()
    holders = 0
  }
  if (activeWorkspace === null) start(workspaceId)
  holders += 1
  let released = false
  return () => {
    if (released || activeWorkspace !== workspaceId) return
    released = true
    holders -= 1
    if (holders <= 0) stop()
  }
}

export const requestCatalogRefresh = () => schedule(0)
TS_END

cat > "$OUT_DIR/catalogWrite.ts" <<'TS_END'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '@@DB@@'
import { supabase } from '@@SUPABASE@@'
import {
  CATEGORY_COLUMNS,
  PRODUCT_COLUMNS,
  UNIT_COLUMNS,
  isOnline,
} from './catalogStore'
import { mapWriteError } from './errors'
import { priceToWire, productPatchToColumns, toProductRow, type ProductPatch, type ServerProduct } from './rows'
import type { CatalogError, CategoryRow, ProductRow, Result, UnitRow } from './types'

const sb = supabase as unknown as SupabaseClient

interface Spec<R> {
  table: string
  columns: string
  adapt: (raw: unknown) => R
  store: (row: R) => Promise<unknown>
}

const categorySpec: Spec<CategoryRow> = {
  table: 'categories',
  columns: CATEGORY_COLUMNS,
  adapt: (r) => r as CategoryRow,
  store: (r) => getDb().categories.put(r),
}
const unitSpec: Spec<UnitRow> = {
  table: 'units',
  columns: UNIT_COLUMNS,
  adapt: (r) => r as UnitRow,
  store: (r) => getDb().units.put(r),
}
const productSpec: Spec<ProductRow> = {
  table: 'products',
  columns: PRODUCT_COLUMNS,
  adapt: (r) => toProductRow(r as ServerProduct),
  store: (r) => getDb().products.put(r),
}

const fail = <T>(error: CatalogError): Result<T> => ({ ok: false, error })
const OFFLINE: CatalogError = {
  code: 'OFFLINE',
  message: 'Mengubah katalog memerlukan koneksi internet. Sambungkan perangkat, lalu coba lagi.',
}
// 0 baris berubah berarti RLS menolak tanpa galat (Bagian 3, bagian 8).
const NO_ROWS: CatalogError = {
  code: 'ROWS_NOT_AFFECTED',
  message: 'Perubahan ditolak server. Anda mungkin tidak berhak mengubah data ini, atau datanya sudah tidak ada.',
}

// Cache lokal hanya cermin; bila gagal ditulis, Realtime dan penyegaran berikutnya memperbaikinya.
async function mirror<R>(spec: Spec<R>, row: R) {
  try {
    await spec.store(row)
  } catch {
    /* sengaja diabaikan */
  }
}

async function insertOne<R>(spec: Spec<R>, row: Record<string, unknown>): Promise<Result<R>> {
  if (!isOnline()) return fail(OFFLINE)
  try {
    const { data, error } = await sb.from(spec.table).insert(row).select(spec.columns).single()
    if (error) return fail(mapWriteError(error))
    const saved = spec.adapt(data)
    await mirror(spec, saved)
    return { ok: true, data: saved }
  } catch (e) {
    return fail(mapWriteError(e as { message?: string }))
  }
}

async function updateOne<R>(
  spec: Spec<R>,
  workspaceId: string,
  id: string,
  patch: Record<string, unknown>,
): Promise<Result<R>> {
  if (Object.keys(patch).length === 0) {
    return fail({ code: 'KPS_INVALID_INPUT', message: 'Tidak ada perubahan untuk disimpan.' })
  }
  if (!isOnline()) return fail(OFFLINE)
  try {
    const { data, error } = await sb
      .from(spec.table)
      .update(patch)
      .eq('id', id)
      .eq('workspace_id', workspaceId)
      .select(spec.columns)
    if (error) return fail(mapWriteError(error))
    const rows = (data ?? []) as unknown[]
    if (rows.length === 0) return fail(NO_ROWS)
    const saved = spec.adapt(rows[0])
    await mirror(spec, saved)
    return { ok: true, data: saved }
  } catch (e) {
    return fail(mapWriteError(e as { message?: string }))
  }
}

export const createCategory = (workspaceId: string, v: { name: string }) =>
  insertOne(categorySpec, { workspace_id: workspaceId, name: v.name })

export const updateCategory = (
  workspaceId: string,
  id: string,
  patch: { name?: string; is_archived?: boolean },
) => updateOne(categorySpec, workspaceId, id, { ...patch })

export const createUnit = (workspaceId: string, v: { name: string; allow_fraction: boolean }) =>
  insertOne(unitSpec, { workspace_id: workspaceId, name: v.name, allow_fraction: v.allow_fraction })

export const updateUnit = (
  workspaceId: string,
  id: string,
  patch: { name?: string; allow_fraction?: boolean; is_archived?: boolean },
) => updateOne(unitSpec, workspaceId, id, { ...patch })

export const createProduct = (
  workspaceId: string,
  v: { name: string; categoryId: string; unitId: string; price: string | null },
) =>
  insertOne(productSpec, {
    workspace_id: workspaceId,
    name: v.name,
    category_id: v.categoryId,
    unit_id: v.unitId,
    price: priceToWire(v.price),
  })

export const updateProduct = (workspaceId: string, id: string, patch: ProductPatch) =>
  updateOne(productSpec, workspaceId, id, productPatchToColumns(patch))
TS_END

cat > "$OUT_DIR/useCatalog.ts" <<'TS_END'
import { useEffect, useState, useSyncExternalStore } from 'react'
import { catalogQuery, describeError } from './catalogStore'
import {
  acquireCatalogSync,
  getSyncState,
  requestCatalogRefresh,
  subscribeSyncState,
  type SyncState,
} from './catalogSync'
import type { CatalogData } from './types'

export function useCatalogSyncState(): SyncState {
  return useSyncExternalStore(subscribeSyncState, getSyncState, getSyncState)
}

// data bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useCatalog(workspaceId: string | null) {
  const [data, setData] = useState<CatalogData | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setData(null)
      return undefined
    }
    const sub = catalogQuery(workspaceId).subscribe({
      next: (value) => {
        setData(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireCatalogSync(workspaceId) : undefined), [workspaceId])

  const sync = useCatalogSyncState()
  return {
    data,
    loading: data === null && readError === null,
    readError,
    sync,
    refresh: requestCatalogRefresh,
  }
}
TS_END

# 4. Uji Vitest
cat > "$OUT_DIR/validation.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { parsePriceInput } from './moneyAdapter'
import { validateCategoryForm, validateProductForm, validateUnitForm } from './validation'

describe('parsePriceInput', () => {
  it.each([
    ['', null],
    ['   ', null],
    ['0', '0'],
    ['12500', '12500'],
    ['12.500', '12500'],
    ['Rp 12.500', '12500'],
    ['1.000.000', '1000000'],
    ['10,00', '10'],
    ['007', '7'],
    ['99999999999999', '99999999999999'],
  ])('menerima %j sebagai %j', (input, expected) => {
    expect(parsePriceInput(input)).toEqual({ ok: true, value: expected })
  })

  it.each(['-1', '10,5', '10.5', '1.00', 'abc', '12 500x', '100000000000000', ',5'])(
    'menolak %j',
    (input) => {
      expect(parsePriceInput(input).ok).toBe(false)
    },
  )
})

describe('validateCategoryForm', () => {
  it('memangkas spasi dan menerima tepat 200 karakter', () => {
    const r = validateCategoryForm({ name: `  ${'a'.repeat(200)}  ` })
    expect(r).toEqual({ ok: true, value: { name: 'a'.repeat(200) } })
  })
  it('menolak kosong dan 201 karakter', () => {
    expect(validateCategoryForm({ name: '   ' }).ok).toBe(false)
    expect(validateCategoryForm({ name: 'a'.repeat(201) }).ok).toBe(false)
  })
  it('menghitung per code point, bukan per unit UTF-16', () => {
    expect(validateCategoryForm({ name: '😀'.repeat(200) }).ok).toBe(true)
    expect(validateCategoryForm({ name: '😀'.repeat(201) }).ok).toBe(false)
  })
})

describe('validateUnitForm', () => {
  it('batas 50 karakter dan membawa allow_fraction', () => {
    expect(validateUnitForm({ name: 'k'.repeat(50), allowFraction: true })).toEqual({
      ok: true,
      value: { name: 'k'.repeat(50), allow_fraction: true },
    })
    expect(validateUnitForm({ name: 'k'.repeat(51), allowFraction: false }).ok).toBe(false)
  })
})

describe('validateProductForm', () => {
  const base = { name: 'Beras 5 kg', categoryId: 'c1', unitId: 'u1', priceText: '65.000' }
  it('menerima isian lengkap dan harga kosong', () => {
    expect(validateProductForm(base)).toEqual({
      ok: true,
      value: { name: 'Beras 5 kg', categoryId: 'c1', unitId: 'u1', price: '65000' },
    })
    expect(validateProductForm({ ...base, priceText: '' })).toMatchObject({ ok: true, value: { price: null } })
  })
  it('mengumpulkan semua galat sekaligus', () => {
    const r = validateProductForm({ name: '', categoryId: '', unitId: '', priceText: '-5' })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(['categoryId', 'name', 'price', 'unitId'])
  })
  it('menolak nama 201 karakter', () => {
    expect(validateProductForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
  })
})
TS_END

cat > "$OUT_DIR/search.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { filterProducts, normalizeText, selectableOptions } from './search'
import type { ProductRow } from './types'

const p = (id: string, name: string, category_id = 'c1', is_archived = false): ProductRow => ({
  id,
  workspace_id: 'w',
  category_id,
  unit_id: 'u',
  name,
  photo_path: null,
  price: null,
  is_archived,
  updated_at: '2026-11-18T00:00:00Z',
})

const data = [
  p('1', 'Gula Pasir 1 kg'),
  p('2', 'Minyak Goreng 2 L', 'c2'),
  p('3', 'Café Susu', 'c2', true),
  p('4', 'beras premium 5 kg'),
]

describe('normalizeText', () => {
  it('menghapus diakritik, huruf besar, dan spasi ganda', () => {
    expect(normalizeText('  Café   SUSU ')).toBe('cafe susu')
  })
})

describe('filterProducts', () => {
  it('tanpa filter mengembalikan semua, terurut menurut nama', () => {
    expect(filterProducts(data).map((x) => x.id)).toEqual(['4', '3', '1', '2'])
  })
  it('mencocokkan semua kata di mana pun posisinya', () => {
    expect(filterProducts(data, { query: 'kg pasir' }).map((x) => x.id)).toEqual(['1'])
    expect(filterProducts(data, { query: 'cafe' }).map((x) => x.id)).toEqual(['3'])
  })
  it('menyaring kategori dan status arsip', () => {
    expect(filterProducts(data, { categoryId: 'c2' }).map((x) => x.id)).toEqual(['3', '2'])
    expect(filterProducts(data, { archive: 'active' }).map((x) => x.id)).not.toContain('3')
    expect(filterProducts(data, { archive: 'archived' }).map((x) => x.id)).toEqual(['3'])
  })
  it('query tanpa hasil memberi larik kosong', () => {
    expect(filterProducts(data, { query: 'tidak ada' })).toEqual([])
  })
})

describe('selectableOptions', () => {
  const rows = [
    { id: 'a', name: 'B', is_archived: false },
    { id: 'b', name: 'A', is_archived: true },
    { id: 'c', name: 'C', is_archived: true },
  ]
  it('hanya yang aktif untuk isian baru', () => {
    expect(selectableOptions(rows).map((r) => r.id)).toEqual(['a'])
  })
  it('mempertahankan nilai yang sedang dipakai walau diarsipkan', () => {
    expect(selectableOptions(rows, 'c').map((r) => r.id)).toEqual(['a', 'c'])
  })
})
TS_END

cat > "$OUT_DIR/errors.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { mapWriteError } from './errors'

describe('mapWriteError', () => {
  it.each([
    [{ message: 'Failed to fetch' }, 'OFFLINE'],
    [{ code: 'PGRST301', message: 'JWT expired' }, 'AUTH_EXPIRED'],
    [{ code: '42501', message: 'new row violates row-level security policy for table "products"' }, 'KPS_FORBIDDEN'],
    [{ code: '23503', message: 'violates foreign key constraint' }, 'KPS_REFERENCE_INVALID'],
    [{ code: '23505', message: 'duplicate key value violates unique constraint "categories_name_active_uq"' }, 'KPS_CONFLICT'],
    [{ code: '23514', message: 'value for domain kps_rupiah violates check constraint "kps_rupiah_check"' }, 'KPS_INVALID_PRICE'],
    [{ code: '23514', message: 'violates check constraint "products_name_len_chk"' }, 'KPS_TEXT_TOO_LONG'],
    [{ code: '23514', message: 'violates check constraint "products_photo_path_fmt_chk"' }, 'KPS_INVALID_PHOTO_PATH'],
    [{ code: '23514', message: 'violates check constraint "lainnya"' }, 'KPS_CHECK_VIOLATION'],
    [{ code: 'P0001', message: 'KPS_REF_ARCHIVED: kategori diarsipkan' }, 'KPS_REF_ARCHIVED'],
    [{ code: '22P02', message: 'invalid input syntax' }, 'KPS_INVALID_INPUT'],
    [{ code: 'XX000', message: 'boom' }, 'UNKNOWN'],
    [null, 'UNKNOWN'],
  ])('memetakan %j ke %s', (raw, code) => {
    expect(mapWriteError(raw).code).toBe(code)
  })

  it('membedakan pesan nama kategori dan nama satuan yang bentrok', () => {
    const k = mapWriteError({ code: '23505', message: 'constraint "categories_name_active_uq"' })
    const u = mapWriteError({ code: '23505', message: 'constraint "units_name_active_uq"' })
    expect(k.message).toContain('kategori')
    expect(u.message).toContain('satuan')
  })

  it('tidak memakai karakter em dash pada pesan', () => {
    expect(mapWriteError({ code: '42501' }).message).not.toContain('\u2014')
  })
})
TS_END

cat > "$OUT_DIR/rows.test.ts" <<'TS_END'
import { describe, expect, it } from 'vitest'
import { productPatchToColumns, toProductRow } from './rows'

const server = {
  id: 'p',
  workspace_id: 'w',
  category_id: 'c',
  unit_id: 'u',
  name: 'Gula',
  photo_path: null,
  is_archived: false,
  updated_at: '2026-11-18T00:00:00Z',
}

describe('toProductRow', () => {
  it('mengubah harga angka menjadi string dan mempertahankan null', () => {
    expect(toProductRow({ ...server, price: 12500 }).price).toBe('12500')
    expect(toProductRow({ ...server, price: 0 }).price).toBe('0')
    expect(toProductRow({ ...server, price: null }).price).toBeNull()
  })
})

describe('productPatchToColumns', () => {
  it('hanya memuat kolom yang diubah dan memetakan nama kolom', () => {
    expect(productPatchToColumns({ categoryId: 'c2', isArchived: true })).toEqual({
      category_id: 'c2',
      is_archived: true,
    })
  })
  it('mengosongkan harga mengirim null dan harga 0 tetap 0', () => {
    expect(productPatchToColumns({ price: null })).toEqual({ price: null })
    expect(productPatchToColumns({ price: '0' })).toEqual({ price: 0 })
  })
  it('patch kosong menghasilkan objek kosong', () => {
    expect(productPatchToColumns({})).toEqual({})
  })
})
TS_END

# 5. Isi jalur relatif ke berkas yang baru dibuat
for f in "$OUT_DIR"/*.ts; do
  sed -i -e "s#@@MONEY@@#$REL_MONEY#g" -e "s#@@DB@@#$REL_DB#g" -e "s#@@SUPABASE@@#$REL_SUPABASE#g" "$f"
done

# 6. Terapkan patch db.ts (terakhir)
node "$PATCH_JS" apply "$DB_FILE" "$TYPES_FROM_DB"

echo
echo "Selesai. Berkas baru di $OUT_DIR, $DB_FILE dipatch ke Dexie versi 2."
if ! grep -q '"vitest"' package.json; then
  echo "PERHATIAN: vitest belum ada di package.json. Jalankan: npm i -D vitest, lalu tambahkan skrip \"test\": \"vitest run\"."
fi
echo "Berikutnya: npx tsc --noEmit -p . && npx vitest run src/features/katalog"
