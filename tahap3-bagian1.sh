#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }
once() { [ "$(grep -cF -- "$2" "$1")" = "1" ] || fail "$1: pola harus tepat satu baris: $2"; }

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
for f in package.json src/lib/db.ts src/lib/money.ts src/lib/supabase.ts src/lib/sync-errors.ts \
  src/lib/queue-types.ts src/features/katalog/types.ts src/features/katalog/catalogStore.ts \
  src/features/katalog/catalogSync.ts src/features/katalog/useCatalog.ts src/features/katalog/validation.ts; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
[ ! -e src/features/daftar ] || fail "src/features/daftar sudah ada; tidak ditimpa"

for dep in '"vitest"' '"decimal.js"' '"dexie"' '"@supabase/supabase-js"' '"react"'; do
  grep -qF -- "$dep" package.json || fail "package.json tidak memuat $dep"
done

need src/lib/money.ts 'export const D ='
need src/lib/money.ts 'export function subtotal('
need src/lib/money.ts 'export function sumSubtotals('
need src/lib/money.ts 'export function parseAmount('
need src/lib/sync-errors.ts 'export function normalizeSendError('
need src/lib/sync-errors.ts 'export function classifyOutcome('
need src/lib/sync-errors.ts 'export type SendError'
need src/lib/sync-errors.ts 'export type SendResult'
need src/features/katalog/catalogStore.ts 'export const isOnline'
need src/features/katalog/catalogStore.ts 'export function describeError'
need src/features/katalog/catalogSync.ts 'export interface SyncState'
need src/features/katalog/useCatalog.ts 'export function useCatalog('
need src/features/katalog/types.ts 'export interface CatalogData'
need src/features/katalog/validation.ts 'export type FormResult'
need src/lib/db.ts "import { LOCAL_DB_NAME } from './constants';"

once src/lib/db.ts "import type { QueuedOp } from './queue-types';"
once src/lib/db.ts "declare ops: Table<QueuedOp, string>;"
once src/lib/db.ts "products: 'id, workspace_id, category_id, unit_id, name',"
! grep -qF 'version(3)' src/lib/db.ts || fail "src/lib/db.ts sudah memuat version(3)"
! grep -qF 'listItems' src/lib/db.ts || fail "src/lib/db.ts sudah memuat listItems"

# --- Penulisan ---
mkdir -p src/features/daftar

cat > src/features/daftar/types.ts <<'EOF'
// Barang daftar aktif: belum dihapus dan belum dipindahkan ke sesi.
export interface ListItemRow {
  id: string
  workspace_id: string
  shopping_list_id: string
  product_id: string | null
  manual_name: string | null
  manual_unit: string | null
  photo_path: string | null
  note: string | null
  // numeric dari server disimpan lokal sebagai string desimal, bukan float (FR-038).
  quantity_needed: string
  created_at: string
  updated_at: string
}

export interface ServerListItem extends Omit<ListItemRow, 'quantity_needed'> {
  quantity_needed: number | string
}

// Batas BR-039. Satuan manual 50 karena disalin ke unit_snapshot.
export const LIST_TEXT_LIMITS = { itemName: 200, manualUnit: 50, note: 1000 } as const

export type ListOpType =
  | 'add_catalog_to_list'
  | 'list_add_manual'
  | 'list_set_quantity'
  | 'list_delete'
  | 'list_set_photo'

// retryable true: operasi mungkin sudah sampai ke server, kirim ulang dengan opId yang sama.
export type ListOpResult =
  | { ok: true; opId: string; data: Record<string, unknown>; replayed: boolean }
  | { ok: false; opId: string; code: string; message: string; retryable: boolean }
EOF

cat > src/features/daftar/rows.ts <<'EOF'
import { D } from '../../lib/money'
import type { ListItemRow, ServerListItem } from './types'

// PostgREST mengirim numeric sebagai angka JSON; disimpan lokal sebagai string.
export function toListItemRow(r: ServerListItem): ListItemRow {
  return { ...r, quantity_needed: new D(r.quantity_needed).toString() }
}

// Kuantitas maksimal 3 desimal dan di bawah 1 miliar, aman sebagai Number.
export const quantityToWire = (q: string): number => Number(q)
EOF

cat > src/features/daftar/payloads.ts <<'EOF'
import { quantityToWire } from './rows'

// Kunci payload mengikuti tabel operasi di KPS-DB-Bagian-3, bagian 5.
export function addCatalogPayload(productId: string, quantity: string): Record<string, unknown> {
  return { product_id: productId, quantity: quantityToWire(quantity) }
}

export function addManualPayload(input: {
  id: string
  name: string
  unit: string
  quantity: string
  note: string | null
  photoPath: string | null
}): Record<string, unknown> {
  const p: Record<string, unknown> = {
    id: input.id,
    name: input.name,
    unit: input.unit,
    quantity: quantityToWire(input.quantity),
  }
  if (input.note !== null) p.note = input.note
  if (input.photoPath !== null) p.photo_path = input.photoPath
  return p
}

export const setQuantityPayload = (itemId: string, quantity: string): Record<string, unknown> => ({
  item_id: itemId,
  quantity: quantityToWire(quantity),
})

export const deletePayload = (itemId: string): Record<string, unknown> => ({ item_id: itemId })

export const setPhotoPayload = (itemId: string, photoPath: string): Record<string, unknown> => ({
  item_id: itemId,
  photo_path: photoPath,
})
EOF

cat > src/features/daftar/errors.ts <<'EOF'
import type { SendError } from '../../lib/sync-errors'

const MESSAGES: Record<string, string> = {
  KPS_FORBIDDEN: 'Akun Anda tidak berhak melakukan perubahan ini.',
  KPS_INVALID_INPUT: 'Data yang dikirim tidak valid.',
  KPS_UNKNOWN_OP: 'Jenis perubahan tidak dikenali server.',
  KPS_OP_ID_CONFLICT: 'Perubahan ini bentrok dengan perubahan lain. Muat ulang lalu coba lagi.',
  KPS_INTERNAL: 'Server sedang bermasalah. Coba lagi sebentar lagi.',
  KPS_DEPENDENCY_MISSING: 'Perubahan sebelumnya belum diproses server. Coba lagi.',
  KPS_DEPENDENCY_REJECTED: 'Perubahan sebelumnya ditolak, jadi perubahan ini tidak dikirim.',
  KPS_TARGET_NOT_FOUND: 'Barang tidak ditemukan. Mungkin sudah dihapus atau dipindahkan.',
  KPS_ITEM_DELETED: 'Barang ini sudah dihapus. Tambahkan lagi bila masih diperlukan.',
  KPS_ITEM_MOVED: 'Barang ini sudah dipindahkan ke sesi belanja, jadi tidak dapat diubah dari daftar.',
  KPS_PRODUCT_ARCHIVED: 'Barang ini sudah diarsipkan dan tidak dapat ditambahkan lagi.',
  KPS_FRACTION_NOT_ALLOWED: 'Satuan barang ini tidak menerima jumlah berpecahan.',
  KPS_INVALID_QUANTITY: 'Jumlah harus lebih dari 0 dan paling banyak 3 angka di belakang koma.',
  KPS_TEXT_TOO_LONG: 'Teks terlalu panjang. Nama maksimal 200 karakter, satuan 50, catatan 1000.',
  KPS_CONFLICT: 'Data ini sudah ada. Muat ulang lalu coba lagi.',
  KPS_PHOTO_NOT_FOUND: 'Berkas foto belum ada di penyimpanan. Unggah ulang fotonya.',
  KPS_INVALID_PHOTO_PATH: 'Lokasi foto tidak valid.',
  KPS_INVALID_ITEM_KIND: 'Perubahan ini tidak berlaku untuk jenis barang tersebut.',
  KPS_REFERENCE_INVALID: 'Data yang dirujuk tidak ditemukan.',
  KPS_CHECK_VIOLATION: 'Data tidak memenuhi aturan penyimpanan.',
}

const GENERIC_REJECTED = 'Perubahan ditolak server.'

export function messageForCode(code: string | null | undefined, serverMessage?: string): string {
  if (code) {
    const known = MESSAGES[code]
    if (known) return known
  }
  const fromServer = serverMessage?.trim()
  return fromServer ? fromServer : GENERIC_REJECTED
}

export function messageForSendError(e: SendError): string {
  if (e.network) return 'Tidak dapat terhubung ke server. Periksa koneksi, lalu coba lagi.'
  if (e.kpsCode) return messageForCode(e.kpsCode)
  if (e.sqlState === '42501' || e.httpStatus === 401 || e.httpStatus === 403) {
    return 'Akses ditolak. Keluar lalu masuk kembali bila terus berulang.'
  }
  return 'Server sedang bermasalah. Coba lagi sebentar lagi.'
}
EOF

cat > src/features/daftar/submitCore.ts <<'EOF'
import { classifyOutcome, normalizeSendError, type SendResult } from '../../lib/sync-errors'
import { messageForCode, messageForSendError } from './errors'
import type { ListOpResult, ListOpType } from './types'

export interface RpcReply {
  data: unknown
  error: unknown
  status?: number
}

export interface SubmitDeps {
  rpc: (args: {
    p_workspace_id: string
    p_op_id: string
    p_op_type: string
    p_payload: Record<string, unknown>
  }) => Promise<RpcReply>
  refreshSession: () => Promise<boolean>
  isOnline: () => boolean
  newId: () => string
}

export interface SubmitOptions {
  // Kirim ulang dengan opId yang sama setelah retryable: server menjawab replay, tanpa duplikasi (SYNC-004).
  opId?: string
}

type Body = Record<string, unknown>

function bodyOf(reply: RpcReply | null): Body | null {
  const b = reply?.data
  return typeof b === 'object' && b !== null ? (b as Body) : null
}

function toSendResult(reply: RpcReply): SendResult {
  if (reply.error) return { kind: 'error', error: normalizeSendError(reply.error, reply.status) }
  const b = bodyOf(reply)
  if (b && typeof b.status === 'string') {
    return { kind: 'response', status: b.status, code: typeof b.code === 'string' ? b.code : null }
  }
  return { kind: 'response', status: 'unknown' }
}

export function createSubmitter(deps: SubmitDeps) {
  return async function submit(
    workspaceId: string,
    opType: ListOpType,
    payload: Record<string, unknown>,
    options: SubmitOptions = {},
  ): Promise<ListOpResult> {
    const opId = options.opId ?? deps.newId()
    const fail = (code: string, message: string, retryable: boolean): ListOpResult => ({
      ok: false,
      opId,
      code,
      message,
      retryable,
    })

    if (!deps.isOnline()) {
      return fail('OFFLINE', 'Anda sedang offline. Menulis daftar memerlukan koneksi internet.', false)
    }

    let refreshed = false
    for (;;) {
      let reply: RpcReply | null = null
      let result: SendResult
      try {
        reply = await deps.rpc({
          p_workspace_id: workspaceId,
          p_op_id: opId,
          p_op_type: opType,
          p_payload: payload,
        })
        result = toSendResult(reply)
      } catch (e) {
        result = { kind: 'error', error: normalizeSendError(e) }
      }

      const action = classifyOutcome(result, { sessionRefreshed: refreshed })
      switch (action.type) {
        case 'success': {
          const b = bodyOf(reply)
          const data = b && typeof b.data === 'object' && b.data !== null ? (b.data as Body) : {}
          return { ok: true, opId, data, replayed: b?.replayed === true }
        }
        case 'fail_rejected': {
          const msg = bodyOf(reply)?.message
          return fail(
            action.code ?? 'KPS_REJECTED',
            messageForCode(action.code, typeof msg === 'string' ? msg : undefined),
            false,
          )
        }
        case 'fail_invalid':
          return fail(action.code, messageForCode(action.code), false)
        case 'fail_forbidden':
          return fail('KPS_FORBIDDEN', messageForCode('KPS_FORBIDDEN'), false)
        case 'refresh_and_resend': {
          const ok = await deps.refreshSession()
          if (!ok) {
            return fail('SESSION_EXPIRED', 'Sesi login tidak dapat disegarkan. Keluar lalu masuk kembali.', false)
          }
          refreshed = true
          continue
        }
        case 'needs_login':
          return fail('SESSION_EXPIRED', 'Sesi login berakhir. Keluar lalu masuk kembali.', false)
        case 'retry': {
          if (result.kind === 'error') {
            return fail(result.error.network ? 'NETWORK' : 'SERVER_ERROR', messageForSendError(result.error), true)
          }
          return fail('SERVER_ERROR', 'Jawaban server tidak dikenali. Coba lagi.', true)
        }
      }
    }
  }
}
EOF

cat > src/features/daftar/submitListOp.ts <<'EOF'
import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { isOnline } from '../katalog/catalogStore'
import { requestListRefresh } from './listSync'
import { createSubmitter, type SubmitOptions } from './submitCore'
import type { ListOpResult, ListOpType } from './types'

const sb = supabase as unknown as SupabaseClient | null

const core = createSubmitter({
  rpc: async (args) => {
    const res = await (sb as SupabaseClient).rpc('kps_apply_op', args)
    return { data: res.data as unknown, error: res.error as unknown, status: res.status }
  },
  refreshSession: async () => {
    const { data, error } = await (sb as SupabaseClient).auth.refreshSession()
    return !error && data.session !== null
  },
  isOnline,
  newId: () => crypto.randomUUID(),
})

// Titik tunggal penulisan daftar. Tahap 6 mengganti isinya menjadi antrean offline; layar tidak berubah.
export function submitListOp(
  workspaceId: string,
  opType: ListOpType,
  payload: Record<string, unknown>,
  options: SubmitOptions = {},
): Promise<ListOpResult> {
  if (!sb) {
    return Promise.resolve({
      ok: false,
      opId: options.opId ?? crypto.randomUUID(),
      code: 'NO_CLIENT',
      message: 'Supabase belum dikonfigurasi.',
      retryable: false,
    })
  }
  return core(workspaceId, opType, payload, options).then((r) => {
    if (r.ok) requestListRefresh()
    return r
  })
}
EOF

cat > src/features/daftar/listStore.ts <<'EOF'
import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import { toListItemRow } from './rows'
import type { ListItemRow, ServerListItem } from './types'

const sb = supabase as unknown as SupabaseClient

export const LIST_ITEM_COLUMNS =
  'id, workspace_id, shopping_list_id, product_id, manual_name, manual_unit, photo_path, note, quantity_needed, created_at, updated_at'

const PAGE_SIZE = 1000

async function fetchActive(workspaceId: string): Promise<ServerListItem[]> {
  const rows: ServerListItem[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from('shopping_list_items')
      .select(LIST_ITEM_COLUMNS)
      .eq('workspace_id', workspaceId)
      .is('deleted_at', null)
      .is('moved_session_id', null)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as ServerListItem[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Barang yang dihapus atau dipindahkan hilang dari hasil server, jadi baris lokal yang tidak ikut harus dibuang.
export async function refreshList(workspaceId: string): Promise<void> {
  const rows = (await fetchActive(workspaceId)).map(toListItemRow)
  const keep = new Set(rows.map((r) => r.id))
  const db = getDb()
  await db.transaction('rw', db.listItems, async () => {
    const local = await db.listItems.where('workspace_id').equals(workspaceId).primaryKeys()
    const stale = local.filter((id) => !keep.has(id))
    if (stale.length > 0) await db.listItems.bulkDelete(stale)
    await db.listItems.bulkPut(rows)
  })
}

export const listQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<ListItemRow[]> => {
    return getDb().listItems.where('workspace_id').equals(workspaceId).toArray()
  })

export async function clearListLocal(): Promise<void> {
  await getDb().listItems.clear()
}
EOF

cat > src/features/daftar/listSync.ts <<'EOF'
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { describeError, isOnline } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { refreshList } from './listStore'

const sb = supabase as unknown as SupabaseClient

// Mulai atau batal sesi juga mengubah baris ini, jadi satu tabel cukup.
const TABLE = 'shopping_list_items'
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

export const getListSyncState = (): SyncState => state

export function subscribeListSyncState(listener: () => void): () => void {
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
    await refreshList(workspaceId)
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
  const ch = sb
    .channel(`kps-list-${workspaceId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: TABLE, filter: `workspace_id=eq.${workspaceId}` },
      () => schedule(),
    )
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

export function acquireListSync(workspaceId: string): () => void {
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

export const requestListRefresh = () => schedule(0)
EOF

cat > src/features/daftar/listView.ts <<'EOF'
import { subtotal, sumSubtotals } from '../../lib/money'
import type { CatalogData } from '../katalog/types'
import type { ListItemRow } from './types'

export interface ListViewRow {
  id: string
  kind: 'catalog' | 'manual'
  productId: string | null
  name: string
  unitName: string
  quantity: string
  note: string | null
  photoPath: string | null
  // Harga katalog saat ini; null untuk barang manual dan barang katalog tanpa harga (FR-018, FR-019).
  price: string | null
  subtotal: string | null
  archived: boolean
  allowFraction: boolean
  // Produk belum ada di katalog lokal.
  unresolved: boolean
}

export interface ListSummary {
  total: string
  pricedCount: number
  unpricedCount: number
  itemCount: number
  incomplete: boolean
}

export interface ListView {
  rows: ListViewRow[]
  summary: ListSummary
}

type Money = ReturnType<typeof subtotal>

function safeSubtotal(price: string | null, quantity: string): Money {
  if (price === null) return null
  try {
    return subtotal(price, quantity)
  } catch {
    return null
  }
}

// FR-046
export const unpricedLabel = (n: number): string => `Belum mencakup ${n} barang tanpa harga`

export function buildListView(items: ListItemRow[], catalog: CatalogData): ListView {
  const products = new Map(catalog.products.map((p) => [p.id, p]))
  const units = new Map(catalog.units.map((u) => [u.id, u]))
  const subs: Money[] = []

  const rows: ListViewRow[] = items.map((it) => {
    if (it.product_id === null) {
      subs.push(null)
      return {
        id: it.id,
        kind: 'manual',
        productId: null,
        name: it.manual_name ?? '',
        unitName: it.manual_unit ?? '',
        quantity: it.quantity_needed,
        note: it.note,
        photoPath: it.photo_path,
        price: null,
        subtotal: null,
        archived: false,
        allowFraction: true,
        unresolved: false,
      }
    }
    const p = products.get(it.product_id)
    const unit = p ? units.get(p.unit_id) : undefined
    const sub = safeSubtotal(p?.price ?? null, it.quantity_needed)
    subs.push(sub)
    return {
      id: it.id,
      kind: 'catalog',
      productId: it.product_id,
      name: p ? p.name : 'Barang tidak ditemukan di katalog lokal',
      unitName: unit?.name ?? '',
      quantity: it.quantity_needed,
      note: it.note,
      photoPath: p?.photo_path ?? null,
      price: p?.price ?? null,
      subtotal: sub === null ? null : sub.toFixed(0),
      archived: p?.is_archived ?? false,
      allowFraction: unit?.allow_fraction ?? false,
      unresolved: p === undefined,
    }
  })

  const pricedCount = subs.filter((s) => s !== null).length
  const unpricedCount = rows.length - pricedCount
  rows.sort((a, b) => a.name.localeCompare(b.name, 'id') || a.id.localeCompare(b.id))

  return {
    rows,
    summary: {
      total: sumSubtotals(subs).toFixed(0),
      pricedCount,
      unpricedCount,
      itemCount: rows.length,
      incomplete: unpricedCount > 0,
    },
  }
}
EOF

cat > src/features/daftar/useList.ts <<'EOF'
import { useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { describeError } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { useCatalog } from '../katalog/useCatalog'
import { listQuery } from './listStore'
import { acquireListSync, getListSyncState, requestListRefresh, subscribeListSyncState } from './listSync'
import { buildListView, type ListView } from './listView'
import type { ListItemRow } from './types'

export function useListSyncState(): SyncState {
  return useSyncExternalStore(subscribeListSyncState, getListSyncState, getListSyncState)
}

// items bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useListItems(workspaceId: string | null) {
  const [items, setItems] = useState<ListItemRow[] | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setItems(null)
      return undefined
    }
    const sub = listQuery(workspaceId).subscribe({
      next: (value) => {
        setItems(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireListSync(workspaceId) : undefined), [workspaceId])

  return { items, readError, sync: useListSyncState(), refresh: requestListRefresh }
}

// Daftar digabung dengan katalog lokal untuk nama, satuan, foto, dan harga.
export function useDaftar(workspaceId: string | null) {
  const catalog = useCatalog(workspaceId)
  const list = useListItems(workspaceId)

  const view: ListView | null = useMemo(
    () => (list.items && catalog.data ? buildListView(list.items, catalog.data) : null),
    [list.items, catalog.data],
  )
  const readError = list.readError ?? catalog.readError

  return {
    view,
    loading: view === null && readError === null,
    readError,
    sync: list.sync,
    catalogSync: catalog.sync,
    refresh: () => {
      list.refresh()
      catalog.refresh()
    },
  }
}
EOF

cat > src/features/daftar/validation.ts <<'EOF'
import { D } from '../../lib/money'
import type { FormResult } from '../katalog/validation'
import { LIST_TEXT_LIMITS } from './types'

// Panjang dihitung per code point, sama dengan char_length di PostgreSQL.
const charCount = (s: string) => Array.from(s).length
const MAX_QTY = new D('1000000000')

export type QuantityResult = { ok: true; value: string } | { ok: false; message: string }

// Koma dan titik sama-sama dianggap pemisah desimal. Pemisah ribuan tidak didukung.
export function parseQuantityInput(text: string, opts: { allowFraction: boolean }): QuantityResult {
  const raw = text.trim().replace(',', '.')
  if (raw === '') return { ok: false, message: 'Jumlah wajib diisi.' }
  if (!/^(\d+(\.\d+)?|\.\d+)$/.test(raw)) {
    return { ok: false, message: 'Jumlah harus berupa angka positif, misalnya 2 atau 1,5.' }
  }
  const d = new D(raw)
  if (d.decimalPlaces() > 3) return { ok: false, message: 'Jumlah maksimal 3 angka di belakang koma.' }
  if (d.lte(0)) return { ok: false, message: 'Jumlah harus lebih dari 0.' }
  if (d.gte(MAX_QTY)) return { ok: false, message: 'Jumlah terlalu besar.' }
  if (!opts.allowFraction && !d.isInteger()) {
    return { ok: false, message: 'Satuan ini tidak menerima jumlah berpecahan.' }
  }
  return { ok: true, value: d.toString() }
}

export function validateCatalogAddForm(input: {
  productId: string
  quantityText: string
  allowFraction: boolean
}): FormResult<{ productId: string; quantity: string }, 'productId' | 'quantity'> {
  const errors: Partial<Record<'productId' | 'quantity', string>> = {}
  if (!input.productId) errors.productId = 'Pilih barang dari katalog.'
  const q = parseQuantityInput(input.quantityText, { allowFraction: input.allowFraction })
  if (!q.ok) errors.quantity = q.message
  if (errors.productId || !q.ok) return { ok: false, errors }
  return { ok: true, value: { productId: input.productId, quantity: q.value } }
}

export interface ManualItemValue {
  name: string
  unit: string
  quantity: string
  note: string | null
}

type ManualKey = 'name' | 'unit' | 'quantity' | 'note'

export function validateManualItemForm(input: {
  name: string
  unit: string
  quantityText: string
  note: string
}): FormResult<ManualItemValue, ManualKey> {
  const errors: Partial<Record<ManualKey, string>> = {}
  const name = input.name.trim()
  const unit = input.unit.trim()
  const note = input.note.trim()
  const L = LIST_TEXT_LIMITS

  if (name === '') errors.name = 'Nama barang wajib diisi.'
  else if (charCount(name) > L.itemName) errors.name = `Nama barang maksimal ${L.itemName} karakter.`

  if (unit === '') errors.unit = 'Satuan wajib diisi.'
  else if (charCount(unit) > L.manualUnit) errors.unit = `Satuan maksimal ${L.manualUnit} karakter.`

  if (charCount(note) > L.note) errors.note = `Catatan maksimal ${L.note} karakter.`

  const q = parseQuantityInput(input.quantityText, { allowFraction: true })
  if (!q.ok) errors.quantity = q.message

  if (Object.keys(errors).length > 0 || !q.ok) return { ok: false, errors }
  return { ok: true, value: { name, unit, quantity: q.value, note: note === '' ? null : note } }
}
EOF

# --- Uji Vitest ---
cat > src/features/daftar/listView.test.ts <<'EOF'
import { describe, expect, it } from 'vitest'
import type { CatalogData, ProductRow } from '../katalog/types'
import { buildListView, unpricedLabel } from './listView'
import type { ListItemRow } from './types'

const WS = 'w1'

function product(id: string, price: string | null, extra: Partial<ProductRow> = {}): ProductRow {
  return {
    id,
    workspace_id: WS,
    category_id: 'c1',
    unit_id: 'u-kg',
    name: id,
    photo_path: null,
    price,
    is_archived: false,
    updated_at: '',
    ...extra,
  }
}

const catalog = (products: ProductRow[]): CatalogData => ({
  categories: [],
  units: [
    { id: 'u-kg', workspace_id: WS, name: 'kg', is_archived: false, updated_at: '', allow_fraction: true },
    { id: 'u-pcs', workspace_id: WS, name: 'pcs', is_archived: false, updated_at: '', allow_fraction: false },
  ],
  products,
})

function item(id: string, extra: Partial<ListItemRow>): ListItemRow {
  return {
    id,
    workspace_id: WS,
    shopping_list_id: 'l1',
    product_id: null,
    manual_name: null,
    manual_unit: null,
    photo_path: null,
    note: null,
    quantity_needed: '1',
    created_at: '',
    updated_at: '',
    ...extra,
  }
}

describe('buildListView', () => {
  it('membulatkan subtotal per barang menjauhi nol dan menjumlah tanpa pembulatan ulang', () => {
    const v = buildListView(
      [
        item('i1', { product_id: 'p1', quantity_needed: '0.5' }),
        item('i2', { product_id: 'p2', quantity_needed: '2' }),
      ],
      catalog([product('p1', '3333'), product('p2', '1000')]),
    )
    const byId = Object.fromEntries(v.rows.map((r) => [r.id, r.subtotal]))
    expect(byId.i1).toBe('1667')
    expect(byId.i2).toBe('2000')
    expect(v.summary.total).toBe('3667')
    expect(v.summary.unpricedCount).toBe(0)
    expect(v.summary.incomplete).toBe(false)
  })

  it('barang manual dan katalog tanpa harga tidak dihitung nol dan menandai belum lengkap', () => {
    const v = buildListView(
      [
        item('i1', { product_id: 'p1', quantity_needed: '3' }),
        item('i2', { product_id: 'p2' }),
        item('i3', { manual_name: 'Plastik', manual_unit: 'pak', quantity_needed: '1.5' }),
      ],
      catalog([product('p1', '5000'), product('p2', null)]),
    )
    expect(v.summary.total).toBe('15000')
    expect(v.summary.pricedCount).toBe(1)
    expect(v.summary.unpricedCount).toBe(2)
    expect(v.summary.incomplete).toBe(true)
    expect(v.rows.find((r) => r.id === 'i2')?.subtotal).toBeNull()
    expect(v.rows.find((r) => r.id === 'i3')?.subtotal).toBeNull()
    expect(unpricedLabel(v.summary.unpricedCount)).toBe('Belum mencakup 2 barang tanpa harga')
  })

  it('tanpa satu pun barang berharga tetap ditandai belum lengkap', () => {
    const v = buildListView([item('i1', { manual_name: 'A', manual_unit: 'pcs' })], catalog([]))
    expect(v.summary.total).toBe('0')
    expect(v.summary.pricedCount).toBe(0)
    expect(v.summary.incomplete).toBe(true)
  })

  it('harga katalog 0 dianggap berharga', () => {
    const v = buildListView([item('i1', { product_id: 'p1', quantity_needed: '4' })], catalog([product('p1', '0')]))
    expect(v.rows[0]?.subtotal).toBe('0')
    expect(v.summary.unpricedCount).toBe(0)
  })

  it('produk yang belum ada di katalog lokal dihitung tanpa harga', () => {
    const v = buildListView([item('i1', { product_id: 'hilang' })], catalog([]))
    expect(v.rows[0]?.unresolved).toBe(true)
    expect(v.summary.unpricedCount).toBe(1)
  })

  it('membawa penanda arsip dan aturan pecahan dari satuan', () => {
    const v = buildListView(
      [item('i1', { product_id: 'p1' }), item('i2', { product_id: 'p2' })],
      catalog([product('p1', '100', { is_archived: true, unit_id: 'u-pcs' }), product('p2', '100')]),
    )
    const a = v.rows.find((r) => r.id === 'i1')
    const b = v.rows.find((r) => r.id === 'i2')
    expect(a?.archived).toBe(true)
    expect(a?.allowFraction).toBe(false)
    expect(a?.unitName).toBe('pcs')
    expect(b?.allowFraction).toBe(true)
  })

  it('mengurutkan berdasarkan nama', () => {
    const v = buildListView(
      [
        item('i1', { manual_name: 'Gula', manual_unit: 'kg' }),
        item('i2', { manual_name: 'Beras', manual_unit: 'kg' }),
      ],
      catalog([]),
    )
    expect(v.rows.map((r) => r.name)).toEqual(['Beras', 'Gula'])
  })
})
EOF

cat > src/features/daftar/validation.test.ts <<'EOF'
import { describe, expect, it } from 'vitest'
import { parseQuantityInput, validateCatalogAddForm, validateManualItemForm } from './validation'

const frac = { allowFraction: true }
const whole = { allowFraction: false }

describe('parseQuantityInput', () => {
  it('menerima koma dan titik sebagai desimal dan menormalkan nilai', () => {
    expect(parseQuantityInput('1,5', frac)).toEqual({ ok: true, value: '1.5' })
    expect(parseQuantityInput(' 2.0 ', frac)).toEqual({ ok: true, value: '2' })
    expect(parseQuantityInput('.5', frac)).toEqual({ ok: true, value: '0.5' })
    expect(parseQuantityInput('0,001', frac)).toEqual({ ok: true, value: '0.001' })
    expect(parseQuantityInput('999999999,999', frac).ok).toBe(true)
  })

  it('menolak kosong, nol, negatif, bukan angka, dan format ganda', () => {
    for (const bad of ['', '  ', '0', '0,0', '-1', 'abc', '1.2.3', '1,2,3', '1e3']) {
      expect(parseQuantityInput(bad, frac).ok).toBe(false)
    }
  })

  it('menolak lebih dari 3 desimal dan nilai 1 miliar atau lebih', () => {
    expect(parseQuantityInput('0,0001', frac).ok).toBe(false)
    expect(parseQuantityInput('1000000000', frac).ok).toBe(false)
  })

  it('pecahan mengikuti satuan', () => {
    expect(parseQuantityInput('0,5', whole).ok).toBe(false)
    expect(parseQuantityInput('2', whole)).toEqual({ ok: true, value: '2' })
    expect(parseQuantityInput('2,0', whole)).toEqual({ ok: true, value: '2' })
  })
})

describe('validateManualItemForm', () => {
  const base = { name: 'Plastik', unit: 'pak', quantityText: '1,5', note: '' }

  it('menerima pecahan untuk barang manual dan mengubah catatan kosong menjadi null', () => {
    const r = validateManualItemForm(base)
    expect(r).toEqual({ ok: true, value: { name: 'Plastik', unit: 'pak', quantity: '1.5', note: null } })
  })

  it('batas panjang tepat diterima dan lebih satu ditolak (BR-039)', () => {
    expect(validateManualItemForm({ ...base, name: 'a'.repeat(200) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
    expect(validateManualItemForm({ ...base, unit: 'a'.repeat(50) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, unit: 'a'.repeat(51) }).ok).toBe(false)
    expect(validateManualItemForm({ ...base, note: 'a'.repeat(1000) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, note: 'a'.repeat(1001) }).ok).toBe(false)
  })

  it('menghitung panjang per code point', () => {
    expect(validateManualItemForm({ ...base, name: '😀'.repeat(200) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, name: '😀'.repeat(201) }).ok).toBe(false)
  })

  it('mewajibkan nama, satuan, dan jumlah, serta melaporkan semua galat sekaligus', () => {
    const r = validateManualItemForm({ name: '  ', unit: '', quantityText: '', note: '' })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(['name', 'quantity', 'unit'])
  })
})

describe('validateCatalogAddForm', () => {
  it('mewajibkan barang dan memakai aturan pecahan satuan', () => {
    expect(validateCatalogAddForm({ productId: '', quantityText: '1', allowFraction: true }).ok).toBe(false)
    expect(validateCatalogAddForm({ productId: 'p1', quantityText: '0,5', allowFraction: false }).ok).toBe(false)
    expect(validateCatalogAddForm({ productId: 'p1', quantityText: '0,5', allowFraction: true })).toEqual({
      ok: true,
      value: { productId: 'p1', quantity: '0.5' },
    })
  })
})
EOF

cat > src/features/daftar/rows.test.ts <<'EOF'
import { describe, expect, it } from 'vitest'
import {
  addCatalogPayload,
  addManualPayload,
  deletePayload,
  setPhotoPayload,
  setQuantityPayload,
} from './payloads'
import { toListItemRow } from './rows'

describe('toListItemRow', () => {
  it('menyimpan kuantitas sebagai string desimal', () => {
    const base = {
      id: 'i', workspace_id: 'w', shopping_list_id: 'l', product_id: null, manual_name: 'A',
      manual_unit: 'kg', photo_path: null, note: null, created_at: '', updated_at: '',
    }
    expect(toListItemRow({ ...base, quantity_needed: 0.5 }).quantity_needed).toBe('0.5')
    expect(toListItemRow({ ...base, quantity_needed: '2.000' }).quantity_needed).toBe('2')
  })
})

describe('payload operasi daftar', () => {
  it('memakai kunci sesuai kontrak kps_apply_op', () => {
    expect(addCatalogPayload('p1', '1.5')).toEqual({ product_id: 'p1', quantity: 1.5 })
    expect(setQuantityPayload('i1', '3')).toEqual({ item_id: 'i1', quantity: 3 })
    expect(deletePayload('i1')).toEqual({ item_id: 'i1' })
    expect(setPhotoPayload('i1', 'w/u.webp')).toEqual({ item_id: 'i1', photo_path: 'w/u.webp' })
  })

  it('menghilangkan kunci opsional yang kosong pada barang manual', () => {
    const base = { id: 'u1', name: 'Plastik', unit: 'pak', quantity: '2', note: null, photoPath: null }
    expect(addManualPayload(base)).toEqual({ id: 'u1', name: 'Plastik', unit: 'pak', quantity: 2 })
    expect(addManualPayload({ ...base, note: 'tebal', photoPath: 'w/u.jpg' })).toEqual({
      id: 'u1', name: 'Plastik', unit: 'pak', quantity: 2, note: 'tebal', photo_path: 'w/u.jpg',
    })
  })
})
EOF

cat > src/features/daftar/submitCore.test.ts <<'EOF'
import { describe, expect, it } from 'vitest'
import { createSubmitter, type RpcReply, type SubmitDeps } from './submitCore'

type Scripted = RpcReply | Error

function makeDeps(replies: Scripted[], over: Partial<SubmitDeps> = {}) {
  const calls: Array<Parameters<SubmitDeps['rpc']>[0]> = []
  let refreshes = 0
  const deps: SubmitDeps = {
    rpc: async (args) => {
      calls.push(args)
      const next = replies.shift()
      if (!next) throw new Error('tidak ada balasan terjadwal')
      if (next instanceof Error) throw next
      return next
    },
    refreshSession: async () => {
      refreshes += 1
      return true
    },
    isOnline: () => true,
    newId: () => 'op-fixed',
    ...over,
  }
  return { deps, calls, refreshes: () => refreshes }
}

const accepted = (data: Record<string, unknown> = {}, replayed = false): RpcReply => ({
  data: { op_id: 'op-fixed', status: 'diterima', code: null, message: null, data, replayed },
  error: null,
  status: 200,
})
const rejected = (code: string): RpcReply => ({
  data: { op_id: 'op-fixed', status: 'ditolak', code, message: 'pesan server', data: {}, replayed: false },
  error: null,
  status: 200,
})
const failed = (error: unknown, status: number): RpcReply => ({ data: null, error, status })

const run = (deps: SubmitDeps, options = {}) =>
  createSubmitter(deps)('w1', 'list_set_quantity', { item_id: 'i1', quantity: 2 }, options)

describe('submitListOp (inti)', () => {
  it('sukses mengirim p_workspace_id, p_op_id, p_op_type, p_payload dan mengembalikan data', async () => {
    const { deps, calls } = makeDeps([accepted({ item_id: 'i1' })])
    const r = await run(deps)
    expect(r).toEqual({ ok: true, opId: 'op-fixed', data: { item_id: 'i1' }, replayed: false })
    expect(calls).toEqual([
      { p_workspace_id: 'w1', p_op_id: 'op-fixed', p_op_type: 'list_set_quantity', p_payload: { item_id: 'i1', quantity: 2 } },
    ])
  })

  it('meneruskan replayed dari server (SYNC-004)', async () => {
    const { deps } = makeDeps([accepted({}, true)])
    const r = await run(deps)
    expect(r.ok && r.replayed).toBe(true)
  })

  it('penolakan bisnis menjadi galat tidak dapat diulang dengan pesan Indonesia', async () => {
    const { deps, calls } = makeDeps([rejected('KPS_ITEM_MOVED')])
    const r = await run(deps)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.code).toBe('KPS_ITEM_MOVED')
      expect(r.retryable).toBe(false)
      expect(r.message).toContain('sesi belanja')
    }
    expect(calls).toHaveLength(1)
  })

  it('kode penolakan yang tidak dikenal memakai pesan server', async () => {
    const { deps } = makeDeps([rejected('KPS_BARU')])
    const r = await run(deps)
    expect(!r.ok && r.message).toBe('pesan server')
  })

  it('galat jaringan dapat diulang dan opId dari pemanggil dipakai ulang', async () => {
    const { deps, calls } = makeDeps([new TypeError('Failed to fetch')])
    const r = await run(deps, { opId: 'op-given' })
    expect(r).toMatchObject({ ok: false, opId: 'op-given', code: 'NETWORK', retryable: true })
    expect(calls[0]?.p_op_id).toBe('op-given')
  })

  it('KPS_INTERNAL dan jawaban tak dikenal dapat diulang', async () => {
    const a = await run(makeDeps([failed({ code: 'KPS_INTERNAL', message: 'KPS_INTERNAL: x' }, 400)]).deps)
    expect(a).toMatchObject({ ok: false, code: 'SERVER_ERROR', retryable: true })
    const b = await run(makeDeps([{ data: { aneh: true }, error: null, status: 200 }]).deps)
    expect(b).toMatchObject({ ok: false, code: 'SERVER_ERROR', retryable: true })
  })

  it('KPS_FORBIDDEN: sesi disegarkan sekali lalu dikirim ulang dengan op_id sama', async () => {
    const { deps, calls, refreshes } = makeDeps([failed({ code: 'KPS_FORBIDDEN', message: 'x' }, 403), accepted()])
    const r = await run(deps)
    expect(r.ok).toBe(true)
    expect(refreshes()).toBe(1)
    expect(calls).toHaveLength(2)
    expect(calls[1]?.p_op_id).toBe(calls[0]?.p_op_id)
  })

  it('KPS_FORBIDDEN yang berulang setelah refresh berakhir gagal', async () => {
    const e = failed({ code: 'KPS_FORBIDDEN', message: 'x' }, 403)
    const { deps, calls, refreshes } = makeDeps([e, e])
    const r = await run(deps)
    expect(r).toMatchObject({ ok: false, code: 'KPS_FORBIDDEN', retryable: false })
    expect(refreshes()).toBe(1)
    expect(calls).toHaveLength(2)
  })

  it('HTTP 401: token disegarkan lalu dikirim ulang', async () => {
    const { deps, refreshes } = makeDeps([failed({ code: 'PGRST301', message: 'JWT expired' }, 401), accepted()])
    expect((await run(deps)).ok).toBe(true)
    expect(refreshes()).toBe(1)
  })

  it('HTTP 401 berulang atau refresh gagal meminta login ulang', async () => {
    const e = failed({ code: 'PGRST301', message: 'JWT expired' }, 401)
    expect(await run(makeDeps([e, e]).deps)).toMatchObject({ ok: false, code: 'SESSION_EXPIRED' })
    const { deps, calls } = makeDeps([e], { refreshSession: async () => false })
    expect(await run(deps)).toMatchObject({ ok: false, code: 'SESSION_EXPIRED' })
    expect(calls).toHaveLength(1)
  })

  it('KPS_INVALID_INPUT langsung gagal tanpa ulang', async () => {
    const { deps, calls } = makeDeps([failed({ code: 'KPS_INVALID_INPUT', message: 'x' }, 400)])
    expect(await run(deps)).toMatchObject({ ok: false, code: 'KPS_INVALID_INPUT', retryable: false })
    expect(calls).toHaveLength(1)
  })

  it('offline tidak mengirim apa pun', async () => {
    const { deps, calls } = makeDeps([], { isOnline: () => false })
    expect(await run(deps)).toMatchObject({ ok: false, code: 'OFFLINE', retryable: false })
    expect(calls).toHaveLength(0)
  })
})
EOF

# --- Ubah src/lib/db.ts (pola harus cocok tepat satu kali) ---
python3 - <<'PY'
import sys
p = "src/lib/db.ts"
s = open(p, encoding="utf-8").read()

def sub(s, old, new):
    n = s.count(old)
    if n != 1:
        sys.exit("BERHENTI: pola cocok %d kali (harus 1): %r" % (n, old))
    return s.replace(old, new)

s = sub(s,
  "import type { QueuedOp } from './queue-types';",
  "import type { QueuedOp } from './queue-types';\nimport type { ListItemRow } from '../features/daftar/types';")
s = sub(s,
  "declare ops: Table<QueuedOp, string>;",
  "declare ops: Table<QueuedOp, string>;\n  declare listItems: Table<ListItemRow, string>;")
s = sub(s,
  "products: 'id, workspace_id, category_id, unit_id, name',",
  "products: 'id, workspace_id, category_id, unit_id, name',\n    });\n    this.version(3).stores({\n      listItems: 'id, workspace_id, shopping_list_id, product_id',")
open(p, "w", encoding="utf-8").write(s)
PY

echo "Selesai. Jalankan: npx vitest run src/features/daftar && npm run build"