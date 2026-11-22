#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }

B=src/features/belanja
D=src/features/daftar

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
for f in src/lib/db.ts src/lib/money.ts src/lib/queue.ts src/lib/pending-ops.ts src/lib/supabase.ts \
  src/features/katalog/rows.ts src/features/katalog/moneyAdapter.ts src/features/katalog/catalogStore.ts \
  src/features/katalog/catalogSync.ts "$D/types.ts" "$D/rows.ts" "$D/validation.ts" "$D/errors.ts" \
  "$D/submitCore.ts" "$D/attemptRunner.ts" "$D/useListOp.ts" "$D/listSync.ts"; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
[ ! -e "$B" ] || fail "$B sudah ada; tidak ditimpa"

need src/lib/queue.ts 'export async function countBlockingOps('
need src/lib/pending-ops.ts 'export async function countPendingOps('
need src/lib/money.ts 'export function effectivePrice('
need src/lib/money.ts 'export function parseAmount('
need src/lib/money.ts 'export function subtotal('
need src/lib/money.ts 'export function sumSubtotals('
need src/lib/money.ts 'export const D ='
need src/features/katalog/rows.ts 'export const priceToWire'
need src/features/katalog/moneyAdapter.ts 'export function parsePriceInput('
need src/features/katalog/catalogStore.ts 'export const isOnline'
need src/features/katalog/catalogStore.ts 'export function describeError'
need src/features/katalog/catalogSync.ts 'export interface SyncState'
need "$D/types.ts" 'export type ListOpResult'
need "$D/rows.ts" 'export const quantityToWire'
need "$D/validation.ts" 'export function parseQuantityInput('
need "$D/validation.ts" 'export function validateManualItemForm('
need "$D/validation.ts" 'export type QuantityResult'
need "$D/errors.ts" 'export function messageForCode('
need "$D/submitCore.ts" 'export function createSubmitter('
need "$D/attemptRunner.ts" 'export function createAttemptRunner('
need "$D/listSync.ts" 'export const requestListRefresh'
need src/lib/db.ts 'declare listItems:'
need src/lib/db.ts 'this.version(3)'
! grep -qF 'version(4)' src/lib/db.ts || fail "src/lib/db.ts sudah memuat version(4)"
! grep -qF 'sessionItems' src/lib/db.ts || fail "src/lib/db.ts sudah memuat sessionItems"

# Semua patch dicek dulu (tanpa menulis); diterapkan setelah berkas baru siap.
PATCHPY="$(mktemp)"
cat > "$PATCHPY" <<'PY'
import sys
check = len(sys.argv) > 1 and sys.argv[1] == "--check"

EDITS = {
  "src/lib/db.ts": [
    ("import type { ListItemRow } from '../features/daftar/types';",
     "import type { ListItemRow } from '../features/daftar/types';\nimport type { SessionItemRow, SessionRow } from '../features/belanja/types';"),
    ("declare listItems: Table<ListItemRow, string>;",
     "declare listItems: Table<ListItemRow, string>;\n  declare sessions: Table<SessionRow, string>;\n  declare sessionItems: Table<SessionItemRow, string>;"),
    ("listItems: 'id, workspace_id, shopping_list_id, product_id',",
     "listItems: 'id, workspace_id, shopping_list_id, product_id',\n    });\n    this.version(4).stores({\n      sessions: 'id, workspace_id, status',\n      sessionItems: 'id, workspace_id, session_id',"),
  ],
  "src/features/daftar/submitCore.ts": [
    ("import type { ListOpResult, ListOpType } from './types'",
     "import type { ListOpResult } from './types'"),
    ("  newId: () => string",
     "  newId: () => string\n  // Opsional: pesan khusus konteks (misalnya sesi belanja).\n  messageFor?: (code: string | null | undefined, serverMessage?: string) => string\n  offlineMessage?: string"),
    ("opType: ListOpType,",
     "opType: string,"),
    ("const opId = options.opId ?? deps.newId()",
     "const opId = options.opId ?? deps.newId()\n    const say = deps.messageFor ?? messageForCode"),
    ("messageForCode(action.code, typeof msg === 'string' ? msg : undefined),",
     "say(action.code, typeof msg === 'string' ? msg : undefined),"),
    ("return fail(action.code, messageForCode(action.code), false)",
     "return fail(action.code, say(action.code), false)"),
    ("return fail('KPS_FORBIDDEN', messageForCode('KPS_FORBIDDEN'), false)",
     "return fail('KPS_FORBIDDEN', say('KPS_FORBIDDEN'), false)"),
    ("return fail('OFFLINE', 'Anda sedang offline. Menulis daftar memerlukan koneksi internet.', false)",
     "return fail(\n        'OFFLINE',\n        deps.offlineMessage ?? 'Anda sedang offline. Menulis daftar memerlukan koneksi internet.',\n        false,\n      )"),
  ],
  "src/features/daftar/attemptRunner.ts": [
    ("import type { ListOpResult, ListOpType } from './types'",
     "import type { ListOpResult } from './types'"),
    ("type Submit = (type: ListOpType, payload: Payload, options: SubmitOptions) => Promise<ListOpResult>",
     "type Submit<T extends string> = (type: T, payload: Payload, options: SubmitOptions) => Promise<ListOpResult>"),
    ("interface Attempt {\n  opId: string\n  type: ListOpType\n  payload: Payload\n}",
     "interface Attempt<T extends string> {\n  opId: string\n  type: T\n  payload: Payload\n}"),
    ("export function createAttemptRunner(submit: Submit, newId: () => string) {\n  let attempt: Attempt | null = null",
     "export function createAttemptRunner<T extends string = string>(submit: Submit<T>, newId: () => string) {\n  let attempt: Attempt<T> | null = null"),
    ("async function send(a: Attempt): Promise<ListOpResult> {",
     "async function send(a: Attempt<T>): Promise<ListOpResult> {"),
    ("run: (type: ListOpType, payload: Payload)",
     "run: (type: T, payload: Payload)"),
  ],
  "src/features/daftar/useListOp.ts": [
    ("createAttemptRunner(",
     "createAttemptRunner<ListOpType>("),
  ],
}

for path, edits in EDITS.items():
    s = open(path, encoding="utf-8").read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            sys.exit("BERHENTI: %s: pola cocok %d kali (harus 1): %r" % (path, n, old))
        s = s.replace(old, new)
    if not check:
        open(path, "w", encoding="utf-8").write(s)
PY
python3 "$PATCHPY" --check

# --- Penulisan berkas baru ---
mkdir -p "$B"

cat > "$B/types.ts" <<'EOF'
export type SessionStatus = 'active' | 'completed' | 'cancelled'
export type ItemStatus = 'to_buy' | 'in_cart' | 'purchased'
export const ITEM_STATUSES: readonly ItemStatus[] = ['to_buy', 'in_cart', 'purchased']

// Uang dan kuantitas disimpan lokal sebagai string desimal, bukan float (FR-038).
export interface SessionRow {
  id: string
  workspace_id: string
  status: SessionStatus
  started_by: string | null
  started_at: string
  ended_by: string | null
  ended_at: string | null
  // Dibekukan saat sesi dimulai (FR-024, FR-050).
  total_estimate: string | null
  unpriced_items_at_start: number | null
  // Dibekukan saat sesi selesai; kosong untuk sesi aktif dan batal.
  total_actual: string | null
  unpriced_items_purchased: number | null
  created_at: string
  updated_at: string
}

export interface ServerSession extends Omit<SessionRow, 'total_estimate' | 'total_actual'> {
  total_estimate: number | string | null
  total_actual: number | string | null
}

export interface SessionItemRow {
  id: string
  session_id: string
  workspace_id: string
  // Kosong untuk barang yang ditambahkan langsung ke sesi (FR-052).
  source_item_id: string | null
  product_id: string | null
  product_name_snapshot: string
  photo_path_snapshot: string | null
  unit_snapshot: string
  unit_id_snapshot: string | null
  allow_fraction_snapshot: boolean
  note_snapshot: string | null
  price_snapshot: string | null
  price_actual: string | null
  quantity_needed: string
  // Kosong tepat bila status to_buy.
  quantity_actual: string | null
  status: ItemStatus
  // Penghapusan oleh pengguna; hanya untuk barang yang ditambahkan langsung (FR-048).
  deleted_at: string | null
  created_at: string
  updated_at: string
}

export interface ServerSessionItem
  extends Omit<SessionItemRow, 'price_snapshot' | 'price_actual' | 'quantity_needed' | 'quantity_actual'> {
  price_snapshot: number | string | null
  price_actual: number | string | null
  quantity_needed: number | string
  quantity_actual: number | string | null
}

export interface SessionData {
  sessions: SessionRow[]
  items: SessionItemRow[]
}
EOF

cat > "$B/rows.ts" <<'EOF'
import { D } from '../../lib/money'
import type { ServerSession, ServerSessionItem, SessionItemRow, SessionRow } from './types'

const numStr = (v: number | string | null): string | null => (v === null ? null : new D(v).toString())

export function toSessionRow(r: ServerSession): SessionRow {
  return { ...r, total_estimate: numStr(r.total_estimate), total_actual: numStr(r.total_actual) }
}

export function toSessionItemRow(r: ServerSessionItem): SessionItemRow {
  return {
    ...r,
    price_snapshot: numStr(r.price_snapshot),
    price_actual: numStr(r.price_actual),
    quantity_needed: new D(r.quantity_needed).toString(),
    quantity_actual: numStr(r.quantity_actual),
  }
}
EOF

cat > "$B/rows.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { toSessionItemRow, toSessionRow } from './rows'
import type { ServerSession, ServerSessionItem } from './types'

const session: ServerSession = {
  id: 's1', workspace_id: 'w', status: 'active', started_by: 'u', started_at: '', ended_by: null, ended_at: null,
  total_estimate: 15000, unpriced_items_at_start: 2, total_actual: null, unpriced_items_purchased: null,
  created_at: '', updated_at: '',
}

const item: ServerSessionItem = {
  id: 'i1', session_id: 's1', workspace_id: 'w', source_item_id: null, product_id: null,
  product_name_snapshot: 'A', photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null,
  allow_fraction_snapshot: true, note_snapshot: null, price_snapshot: 3333, price_actual: null,
  quantity_needed: 0.5, quantity_actual: '2.000', status: 'in_cart', deleted_at: null, created_at: '', updated_at: '',
}

describe('rows sesi', () => {
  it('mengubah angka server menjadi string desimal dan menjaga null', () => {
    const s = toSessionRow(session)
    expect(s.total_estimate).toBe('15000')
    expect(s.total_actual).toBeNull()
    expect(s.unpriced_items_at_start).toBe(2)
  })

  it('barang sesi: harga dan kuantitas menjadi string, null tetap null', () => {
    const r = toSessionItemRow(item)
    expect(r.price_snapshot).toBe('3333')
    expect(r.price_actual).toBeNull()
    expect(r.quantity_needed).toBe('0.5')
    expect(r.quantity_actual).toBe('2')
  })
})
EOF

cat > "$B/sessionMath.ts" <<'EOF'
import { D, effectivePrice, parseAmount, subtotal, sumSubtotals } from '../../lib/money'
import type { ItemStatus, SessionItemRow } from './types'

export type MathItem = Pick<
  SessionItemRow,
  'status' | 'price_actual' | 'price_snapshot' | 'quantity_actual' | 'quantity_needed' | 'deleted_at' | 'source_item_id'
>

// Satu hitungan FR-050: jumlah dalam baris barang, bukan kuantitas.
export interface Totals {
  total: string
  pricedCount: number
  unpricedCount: number
  incomplete: boolean
}

type Money = ReturnType<typeof subtotal>

function safe<T>(fn: () => T): T | null {
  try {
    return fn()
  } catch {
    return null
  }
}

// Barang yang dihapus pengguna tidak dihitung di mana pun (FR-048, BR-033).
export const isLiveItem = (i: Pick<MathItem, 'deleted_at'>): boolean => i.deleted_at === null

// FR-053: price_actual bila terisi (0 sah), jika tidak price_snapshot.
const actualPrice = (i: MathItem): Money => safe(() => effectivePrice(i.price_actual, i.price_snapshot))
const snapshotPrice = (i: MathItem): Money => safe(() => parseAmount(i.price_snapshot))

export function effectivePriceOf(i: MathItem): string | null {
  const p = actualPrice(i)
  return p === null ? null : p.toFixed(0)
}

// FR-036: pembulatan(harga efektif x jumlah aktual). Null bila harga atau jumlah aktual kosong.
export function itemSubtotal(i: MathItem): string | null {
  const s = safe(() => subtotal(actualPrice(i), i.quantity_actual))
  return s === null ? null : s.toFixed(0)
}

function build(rows: Array<{ price: Money; qty: string | null }>): Totals {
  const subs = rows.map((r) => safe(() => subtotal(r.price, r.qty)))
  const unpricedCount = rows.filter((r) => r.price === null).length
  return {
    total: sumSubtotals(subs).toFixed(0),
    pricedCount: rows.length - unpricedCount,
    unpricedCount,
    incomplete: unpricedCount > 0,
  }
}

// Total berjalan: in_cart dan purchased, harga efektif x jumlah aktual. Dihitung saat ditampilkan.
export function runningTotals(items: MathItem[]): Totals {
  return build(
    items
      .filter((i) => isLiveItem(i) && (i.status === 'in_cart' || i.status === 'purchased'))
      .map((i) => ({ price: actualPrice(i), qty: i.quantity_actual })),
  )
}

// Total aktual: hanya purchased. Pratinjau sebelum sesi selesai; setelah selesai pakai nilai beku di server.
export function actualTotals(items: MathItem[]): Totals {
  return build(
    items
      .filter((i) => isLiveItem(i) && i.status === 'purchased')
      .map((i) => ({ price: actualPrice(i), qty: i.quantity_actual })),
  )
}

// Estimasi awal: price_snapshot x jumlah kebutuhan, hanya barang dari daftar.
// Hanya pemeriksaan silang; tampilan memakai nilai beku dari server (total_estimate, unpriced_items_at_start).
export function startTotals(items: MathItem[]): Totals {
  return build(
    items
      .filter((i) => isLiveItem(i) && i.source_item_id !== null)
      .map((i) => ({ price: snapshotPrice(i), qty: i.quantity_needed })),
  )
}

export function statusCounts(items: Array<Pick<MathItem, 'status' | 'deleted_at'>>): Record<ItemStatus, number> {
  const out: Record<ItemStatus, number> = { to_buy: 0, in_cart: 0, purchased: 0 }
  for (const i of items) if (isLiveItem(i)) out[i.status] += 1
  return out
}

// 3.4.1: Q_sisa = maks(0, dibutuhkan - terbeli); terbeli hanya untuk status purchased.
export function remainderOf(i: MathItem): string {
  const needed = new D(i.quantity_needed)
  const bought = i.status === 'purchased' && i.quantity_actual !== null ? new D(i.quantity_actual) : new D(0)
  const r = needed.minus(bought)
  return r.gt(0) ? r.toString() : '0'
}

// Pratinjau jumlah barang yang kembali ke daftar saat sesi diakhiri atau dibatalkan.
export function returnPreview(items: MathItem[]): { count: number } {
  return { count: items.filter((i) => isLiveItem(i) && new D(remainderOf(i)).gt(0)).length }
}
EOF

cat > "$B/sessionMath.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import {
  actualTotals,
  effectivePriceOf,
  itemSubtotal,
  remainderOf,
  returnPreview,
  runningTotals,
  startTotals,
  statusCounts,
  type MathItem,
} from './sessionMath'

function it_(extra: Partial<MathItem>): MathItem {
  return {
    status: 'to_buy',
    price_actual: null,
    price_snapshot: null,
    quantity_actual: null,
    quantity_needed: '1',
    deleted_at: null,
    source_item_id: 's1',
    ...extra,
  }
}

describe('total berjalan dan total aktual', () => {
  const A = it_({ status: 'in_cart', price_snapshot: '3333', quantity_actual: '0.5' })
  const B = it_({ status: 'purchased', price_actual: '4000', quantity_actual: '3' })
  const C = it_({ status: 'to_buy', price_snapshot: '1000' })
  const D = it_({ status: 'purchased', quantity_actual: '1' })

  it('berjalan memuat in_cart dan purchased berharga, dibulatkan per barang menjauhi nol', () => {
    const t = runningTotals([A, B, C, D])
    expect(t.total).toBe('13667')
    expect(t.pricedCount).toBe(2)
    expect(t.unpricedCount).toBe(1)
    expect(t.incomplete).toBe(true)
  })

  it('aktual hanya purchased', () => {
    const t = actualTotals([A, B, C, D])
    expect(t.total).toBe('12000')
    expect(t.pricedCount).toBe(1)
    expect(t.unpricedCount).toBe(1)
  })

  it('to_buy tidak dihitung walau price_actual terisi', () => {
    const t = runningTotals([it_({ status: 'to_buy', price_actual: '5000' })])
    expect(t).toEqual({ total: '0', pricedCount: 0, unpricedCount: 0, incomplete: false })
  })

  it('barang yang dihapus tidak dihitung, termasuk sebagai barang tanpa harga (CK-11)', () => {
    const N = it_({ status: 'in_cart', price_snapshot: '2000', quantity_actual: '2', source_item_id: null })
    const R = it_({ status: 'purchased', price_snapshot: '900', quantity_actual: '1', source_item_id: null, deleted_at: 'x' })
    const U = it_({ status: 'purchased', quantity_actual: '1', source_item_id: null, deleted_at: 'x' })
    expect(runningTotals([N, R, U])).toEqual({ total: '4000', pricedCount: 1, unpricedCount: 0, incomplete: false })
    expect(actualTotals([N, R, U]).unpricedCount).toBe(0)
  })
})

describe('harga efektif', () => {
  it('price_actual menang atas snapshot dan dapat dikosongkan (CK-03)', () => {
    const base = { status: 'in_cart' as const, price_snapshot: '10000', quantity_actual: '2' }
    expect(itemSubtotal(it_({ ...base, price_actual: '11000' }))).toBe('22000')
    expect(itemSubtotal(it_({ ...base, price_actual: null }))).toBe('20000')
    expect(effectivePriceOf(it_({ ...base, price_actual: '11000' }))).toBe('11000')
  })

  it('price_actual 0 sah: barang berharga dengan subtotal 0 (CK-10)', () => {
    const k = it_({ status: 'purchased', price_snapshot: '9000', price_actual: '0', quantity_actual: '3' })
    expect(itemSubtotal(k)).toBe('0')
    expect(runningTotals([k])).toEqual({ total: '0', pricedCount: 1, unpricedCount: 0, incomplete: false })
  })

  it('tanpa jumlah aktual atau tanpa harga subtotalnya null, tidak pernah 0', () => {
    expect(itemSubtotal(it_({ status: 'to_buy', price_snapshot: '1000' }))).toBeNull()
    expect(itemSubtotal(it_({ status: 'in_cart', quantity_actual: '1' }))).toBeNull()
  })
})

describe('empat hitungan FR-050 tidak tercampur (CK-07)', () => {
  const P1 = it_({ status: 'purchased', price_actual: '2000', quantity_actual: '1', quantity_needed: '1' })
  const P2 = it_({ status: 'purchased', quantity_actual: '1', quantity_needed: '1' })
  const X = it_({ price_snapshot: '5000', quantity_needed: '2' })
  const direct = it_({ source_item_id: null, price_snapshot: '1000', quantity_needed: '5' })

  it('estimasi awal memakai snapshot dan hanya barang dari daftar', () => {
    expect(startTotals([P1, P2])).toEqual({ total: '0', pricedCount: 0, unpricedCount: 2, incomplete: true })
    expect(startTotals([X, direct, it_({ price_snapshot: '1', deleted_at: 'x' })])).toEqual({
      total: '10000',
      pricedCount: 1,
      unpricedCount: 0,
      incomplete: false,
    })
  })

  it('tanpa harga saat mulai berbeda dari tanpa harga yang dibeli', () => {
    expect(startTotals([P1, P2]).unpricedCount).toBe(2)
    expect(actualTotals([P1, P2]).unpricedCount).toBe(1)
  })
})

describe('sisa pengembalian (3.4.1)', () => {
  it('maks(0, dibutuhkan - terbeli) dan pecahan', () => {
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '10', quantity_actual: '8' }))).toBe('2')
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '10', quantity_actual: '12' }))).toBe('0')
    expect(remainderOf(it_({ status: 'in_cart', quantity_needed: '4', quantity_actual: '4' }))).toBe('4')
    expect(remainderOf(it_({ status: 'to_buy', quantity_needed: '5' }))).toBe('5')
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '0.5', quantity_actual: '0.25' }))).toBe('0.25')
  })

  it('pratinjau menghitung baris yang kembali dan melewatkan yang terpenuhi atau dihapus', () => {
    const items = [
      it_({ status: 'to_buy', quantity_needed: '5' }),
      it_({ status: 'purchased', quantity_needed: '3', quantity_actual: '3' }),
      it_({ status: 'to_buy', quantity_needed: '2', deleted_at: 'x', source_item_id: null }),
    ]
    expect(returnPreview(items)).toEqual({ count: 1 })
  })
})

describe('statusCounts', () => {
  it('menghitung hanya barang yang belum dihapus', () => {
    expect(
      statusCounts([
        it_({ status: 'to_buy' }),
        it_({ status: 'in_cart' }),
        it_({ status: 'purchased' }),
        it_({ status: 'purchased', deleted_at: 'x' }),
      ]),
    ).toEqual({ to_buy: 1, in_cart: 1, purchased: 1 })
  })
})
EOF

cat > "$B/sessionSelectors.ts" <<'EOF'
import { isLiveItem } from './sessionMath'
import type { SessionData, SessionItemRow, SessionRow } from './types'

export interface SessionState {
  active: SessionRow | null
  activeItems: SessionItemRow[]
  // Sesi selesai atau batal terbaru, untuk ringkasan setelah sesi berakhir.
  lastEnded: SessionRow | null
  lastEndedItems: SessionItemRow[]
}

const time = (iso: string | null): number => {
  const t = iso === null ? NaN : Date.parse(iso)
  return Number.isNaN(t) ? 0 : t
}

export function selectSessionState(d: SessionData): SessionState {
  const active = d.sessions.find((s) => s.status === 'active') ?? null
  const lastEnded =
    d.sessions
      .filter((s) => s.status !== 'active')
      .sort((a, b) => time(b.ended_at ?? b.created_at) - time(a.ended_at ?? a.created_at))[0] ?? null

  const itemsOf = (s: SessionRow | null): SessionItemRow[] =>
    s === null
      ? []
      : d.items
          .filter((i) => i.session_id === s.id && isLiveItem(i))
          .sort((a, b) => a.product_name_snapshot.localeCompare(b.product_name_snapshot, 'id') || a.id.localeCompare(b.id))

  return { active, activeItems: itemsOf(active), lastEnded, lastEndedItems: itemsOf(lastEnded) }
}
EOF

cat > "$B/sessionSelectors.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { selectSessionState } from './sessionSelectors'
import type { SessionItemRow, SessionRow } from './types'

const session = (id: string, status: SessionRow['status'], ended_at: string | null): SessionRow => ({
  id, workspace_id: 'w', status, started_by: null, started_at: '2026-11-01T00:00:00Z', ended_by: null, ended_at,
  total_estimate: '0', unpriced_items_at_start: 0, total_actual: null, unpriced_items_purchased: null,
  created_at: '2026-11-01T00:00:00Z', updated_at: '',
})

const item = (id: string, session_id: string, name: string, deleted_at: string | null = null): SessionItemRow => ({
  id, session_id, workspace_id: 'w', source_item_id: null, product_id: null, product_name_snapshot: name,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: null, price_actual: null, quantity_needed: '1', quantity_actual: null,
  status: 'to_buy', deleted_at, created_at: '', updated_at: '',
})

describe('selectSessionState', () => {
  it('memisahkan sesi aktif dari sesi berakhir terbaru dan membuang barang yang dihapus', () => {
    const s = selectSessionState({
      sessions: [
        session('a', 'active', null),
        session('c1', 'completed', '2026-11-10T00:00:00Z'),
        session('c2', 'cancelled', '2026-11-12T00:00:00Z'),
      ],
      items: [item('i2', 'a', 'Gula'), item('i1', 'a', 'Beras'), item('i3', 'a', 'Hapus', 'x'), item('i4', 'c2', 'Teh')],
    })
    expect(s.active?.id).toBe('a')
    expect(s.activeItems.map((i) => i.product_name_snapshot)).toEqual(['Beras', 'Gula'])
    expect(s.lastEnded?.id).toBe('c2')
    expect(s.lastEndedItems.map((i) => i.id)).toEqual(['i4'])
  })

  it('tanpa sesi aktif atau sesi apa pun', () => {
    const none = selectSessionState({ sessions: [], items: [] })
    expect(none).toEqual({ active: null, activeItems: [], lastEnded: null, lastEndedItems: [] })
    const onlyEnded = selectSessionState({ sessions: [session('c', 'completed', '2026-11-10T00:00:00Z')], items: [] })
    expect(onlyEnded.active).toBeNull()
    expect(onlyEnded.lastEnded?.id).toBe('c')
  })
})
EOF

cat > "$B/sessionErrors.ts" <<'EOF'
import { messageForCode } from '../daftar/errors'

// Kode khusus sesi. Kode lain jatuh ke tabel pesan daftar.
const SESSION_MESSAGES: Record<string, string> = {
  KPS_SESSION_ALREADY_ACTIVE: 'Sudah ada sesi belanja yang aktif. Muat ulang untuk melihatnya.',
  KPS_SESSION_NOT_ACTIVE:
    'Sesi ini sudah selesai atau dibatalkan, jadi tidak dapat diubah lagi. Perubahan Anda tidak tersimpan.',
  KPS_ITEM_DELETED: 'Barang ini sudah dihapus dari sesi.',
  KPS_TARGET_NOT_FOUND: 'Sesi atau barang tidak ditemukan. Muat ulang untuk melihat keadaan terbaru.',
  KPS_SNAPSHOT_IMMUTABLE:
    'Perubahan ini tidak diizinkan: data awal barang dari daftar tidak dapat diubah, jumlah kebutuhan dan penghapusan hanya untuk barang yang ditambahkan langsung ke sesi, dan foto hanya dapat dipasang sekali.',
  KPS_QUANTITY_ACTUAL_STATE: 'Jumlah aktual hanya dapat diisi untuk barang yang sudah masuk keranjang atau dibeli.',
  KPS_INVALID_PRICE: 'Harga harus Rupiah bulat dan tidak negatif.',
  KPS_SESSION_FROZEN: 'Sesi ini sudah selesai atau dibatalkan, jadi tidak dapat diubah lagi.',
  KPS_SOURCE_NOT_MOVED: 'Data sesi tidak konsisten. Muat ulang lalu coba lagi.',
  KPS_TOTAL_MISMATCH: 'Total sesi tidak cocok dengan hitungan server. Muat ulang lalu coba lagi.',
}

export function sessionMessageForCode(code: string | null | undefined, serverMessage?: string): string {
  if (code) {
    const own = SESSION_MESSAGES[code]
    if (own) return own
  }
  return messageForCode(code, serverMessage)
}
EOF

cat > "$B/sessionErrors.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { sessionMessageForCode } from './sessionErrors'

describe('sessionMessageForCode', () => {
  it('memberi pesan Indonesia untuk penolakan sesi', () => {
    expect(sessionMessageForCode('KPS_SESSION_NOT_ACTIVE')).toContain('selesai atau dibatalkan')
    expect(sessionMessageForCode('KPS_SESSION_ALREADY_ACTIVE')).toContain('sesi belanja yang aktif')
    expect(sessionMessageForCode('KPS_ITEM_DELETED')).toContain('dihapus dari sesi')
    expect(sessionMessageForCode('KPS_INVALID_PRICE')).toContain('Rupiah bulat')
    expect(sessionMessageForCode('KPS_QUANTITY_ACTUAL_STATE')).toContain('keranjang')
  })

  it('kode lain jatuh ke pesan daftar, lalu ke pesan server, lalu ke pesan umum', () => {
    expect(sessionMessageForCode('KPS_FRACTION_NOT_ALLOWED')).toContain('berpecahan')
    expect(sessionMessageForCode('KPS_BARU', 'dari server')).toBe('dari server')
    expect(sessionMessageForCode(null)).toBe('Perubahan ditolak server.')
  })
})
EOF

cat > "$B/sessionRpc.ts" <<'EOF'
import type { SubmitDeps } from '../daftar/submitCore'

// Memiliki RPC sendiri (KPS-DB-Bagian-3, bagian 4).
export type DirectOp =
  | 'kps_start_session'
  | 'kps_end_session'
  | 'kps_cancel_session'
  | 'kps_add_catalog_to_session'

// Lewat kps_apply_op (bagian 5).
export type ApplyOp =
  | 'session_add_manual'
  | 'session_set_status'
  | 'session_set_quantity_actual'
  | 'session_set_price_actual'
  | 'session_set_quantity_needed'
  | 'session_delete_item'
  | 'session_set_photo'

export type SessionOpType = DirectOp | ApplyOp
export type RpcArgs = Parameters<SubmitDeps['rpc']>[0]

export interface RpcCall {
  fn: string
  args: Record<string, unknown>
}

// p_op_type memilih fungsi; kunci payload klien dipetakan ke nama parameter RPC.
export function toRpcCall(a: RpcArgs): RpcCall {
  const base = { p_workspace_id: a.p_workspace_id, p_op_id: a.p_op_id }
  const p = a.p_payload
  switch (a.p_op_type) {
    case 'kps_start_session':
      return { fn: 'kps_start_session', args: base }
    case 'kps_end_session':
    case 'kps_cancel_session':
      return { fn: a.p_op_type, args: { ...base, p_session_id: p.session_id } }
    case 'kps_add_catalog_to_session': {
      const args: Record<string, unknown> = {
        ...base,
        p_session_id: p.session_id,
        p_product_id: p.product_id,
        p_quantity: p.quantity,
      }
      if (typeof p.note === 'string') args.p_note = p.note
      return { fn: 'kps_add_catalog_to_session', args }
    }
    default:
      return { fn: 'kps_apply_op', args: { ...a } }
  }
}
EOF

cat > "$B/sessionRpc.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { toRpcCall } from './sessionRpc'

const base = { p_workspace_id: 'w1', p_op_id: 'o1' }

describe('toRpcCall', () => {
  it('mulai sesi hanya membawa workspace dan op_id', () => {
    expect(toRpcCall({ ...base, p_op_type: 'kps_start_session', p_payload: {} })).toEqual({
      fn: 'kps_start_session',
      args: base,
    })
  })

  it('akhiri dan batalkan membawa p_session_id', () => {
    for (const fn of ['kps_end_session', 'kps_cancel_session']) {
      expect(toRpcCall({ ...base, p_op_type: fn, p_payload: { session_id: 's1' } })).toEqual({
        fn,
        args: { ...base, p_session_id: 's1' },
      })
    }
  })

  it('tambah katalog ke sesi menyertakan p_note hanya bila ada', () => {
    const payload = { session_id: 's1', product_id: 'p1', quantity: 2 }
    expect(toRpcCall({ ...base, p_op_type: 'kps_add_catalog_to_session', p_payload: payload }).args).toEqual({
      ...base,
      p_session_id: 's1',
      p_product_id: 'p1',
      p_quantity: 2,
    })
    expect(
      toRpcCall({ ...base, p_op_type: 'kps_add_catalog_to_session', p_payload: { ...payload, note: 'merah' } }).args,
    ).toMatchObject({ p_note: 'merah' })
  })

  it('operasi lain diteruskan utuh ke kps_apply_op', () => {
    const a = { ...base, p_op_type: 'session_set_status', p_payload: { item_id: 'i1', status: 'in_cart' } }
    expect(toRpcCall(a)).toEqual({ fn: 'kps_apply_op', args: a })
  })
})
EOF

cat > "$B/sessionPayloads.ts" <<'EOF'
import { quantityToWire } from '../daftar/rows'
import { priceToWire } from '../katalog/rows'
import type { ItemStatus } from './types'

type Payload = Record<string, unknown>

// Kunci mengikuti KPS-DB-Bagian-3, bagian 4 dan 5. Untuk operasi lewat kps_apply_op,
// session_id dan product_id berikut dipetakan ke p_session_id dan p_product_id oleh toRpcCall.
export const startSessionPayload = (): Payload => ({})
export const endSessionPayload = (sessionId: string): Payload => ({ session_id: sessionId })
export const cancelSessionPayload = (sessionId: string): Payload => ({ session_id: sessionId })

export function addCatalogToSessionPayload(
  sessionId: string,
  productId: string,
  quantity: string,
  note: string | null,
): Payload {
  const p: Payload = { session_id: sessionId, product_id: productId, quantity: quantityToWire(quantity) }
  if (note !== null) p.note = note
  return p
}

export function addManualToSessionPayload(input: {
  sessionId: string
  id: string
  name: string
  unit: string
  quantity: string
  note: string | null
  photoPath: string | null
}): Payload {
  const p: Payload = {
    session_id: input.sessionId,
    id: input.id,
    name: input.name,
    unit: input.unit,
    quantity: quantityToWire(input.quantity),
  }
  if (input.note !== null) p.note = input.note
  if (input.photoPath !== null) p.photo_path = input.photoPath
  return p
}

export const setStatusPayload = (itemId: string, status: ItemStatus): Payload => ({ item_id: itemId, status })

export const setQuantityActualPayload = (itemId: string, quantity: string): Payload => ({
  item_id: itemId,
  quantity: quantityToWire(quantity),
})

// null mengosongkan harga aktual; 0 sah (FR-053).
export const setPriceActualPayload = (itemId: string, price: string | null): Payload => ({
  item_id: itemId,
  price: priceToWire(price),
})

export const setQuantityNeededPayload = (itemId: string, quantity: string): Payload => ({
  item_id: itemId,
  quantity: quantityToWire(quantity),
})

export const deleteItemPayload = (itemId: string): Payload => ({ item_id: itemId })

export const setSessionPhotoPayload = (itemId: string, photoPath: string): Payload => ({
  item_id: itemId,
  photo_path: photoPath,
})
EOF

cat > "$B/sessionPayloads.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import {
  addCatalogToSessionPayload,
  addManualToSessionPayload,
  cancelSessionPayload,
  deleteItemPayload,
  endSessionPayload,
  setPriceActualPayload,
  setQuantityActualPayload,
  setQuantityNeededPayload,
  setSessionPhotoPayload,
  setStatusPayload,
  startSessionPayload,
} from './sessionPayloads'

describe('payload sesi', () => {
  it('mulai, akhiri, batalkan', () => {
    expect(startSessionPayload()).toEqual({})
    expect(endSessionPayload('s1')).toEqual({ session_id: 's1' })
    expect(cancelSessionPayload('s1')).toEqual({ session_id: 's1' })
  })

  it('tambah katalog ke sesi: note hanya bila ada, kuantitas angka', () => {
    expect(addCatalogToSessionPayload('s1', 'p1', '1.5', null)).toEqual({ session_id: 's1', product_id: 'p1', quantity: 1.5 })
    expect(addCatalogToSessionPayload('s1', 'p1', '2', 'merah')).toEqual({
      session_id: 's1', product_id: 'p1', quantity: 2, note: 'merah',
    })
  })

  it('tambah barang manual ke sesi menghilangkan kunci opsional yang kosong', () => {
    const base = { sessionId: 's1', id: 'u1', name: 'Plastik', unit: 'pak', quantity: '1.5', note: null, photoPath: null }
    expect(addManualToSessionPayload(base)).toEqual({ session_id: 's1', id: 'u1', name: 'Plastik', unit: 'pak', quantity: 1.5 })
    expect(addManualToSessionPayload({ ...base, note: 'tebal', photoPath: 'w/u.jpg' })).toMatchObject({
      note: 'tebal',
      photo_path: 'w/u.jpg',
    })
  })

  it('operasi barang sesi', () => {
    expect(setStatusPayload('i1', 'in_cart')).toEqual({ item_id: 'i1', status: 'in_cart' })
    expect(setQuantityActualPayload('i1', '0.25')).toEqual({ item_id: 'i1', quantity: 0.25 })
    expect(setQuantityNeededPayload('i1', '3')).toEqual({ item_id: 'i1', quantity: 3 })
    expect(deleteItemPayload('i1')).toEqual({ item_id: 'i1' })
    expect(setSessionPhotoPayload('i1', 'w/u.webp')).toEqual({ item_id: 'i1', photo_path: 'w/u.webp' })
  })

  it('harga aktual: null mengosongkan, 0 tetap 0', () => {
    expect(setPriceActualPayload('i1', null)).toEqual({ item_id: 'i1', price: null })
    expect(setPriceActualPayload('i1', '0')).toEqual({ item_id: 'i1', price: 0 })
    expect(setPriceActualPayload('i1', '11000')).toEqual({ item_id: 'i1', price: 11000 })
  })
})
EOF

cat > "$B/sessionValidation.ts" <<'EOF'
import { LIST_TEXT_LIMITS } from '../daftar/types'
import { parseQuantityInput, type QuantityResult } from '../daftar/validation'
import type { FormResult } from '../katalog/validation'

// Harga aktual: kosong berarti mengosongkan (value null), 0 sah, Rupiah bulat (FR-053).
export { parsePriceInput as parsePriceActualInput } from '../katalog/moneyAdapter'
// Nama, satuan, jumlah, dan catatan barang manual di sesi memakai batas yang sama dengan daftar (BR-039).
export { validateManualItemForm as validateSessionManualForm } from '../daftar/validation'
// Jumlah kebutuhan barang yang ditambahkan langsung: lebih dari 0.
export { parseQuantityInput as parseNeededQuantityInput } from '../daftar/validation'

const charCount = (s: string) => Array.from(s).length

// Pecahan mengikuti allow_fraction_snapshot; server tetap penentu. Jumlah aktual 0 diterima (quantity_actual tidak negatif).
export function parseActualQuantityInput(text: string, opts: { allowFraction: boolean }): QuantityResult {
  const raw = text.trim().replace(',', '.')
  if (/^(0+(\.0*)?|\.0+)$/.test(raw)) return { ok: true, value: '0' }
  return parseQuantityInput(text, opts)
}

export function validateSessionCatalogForm(input: {
  productId: string
  quantityText: string
  note: string
  allowFraction: boolean
}): FormResult<{ productId: string; quantity: string; note: string | null }, 'productId' | 'quantity' | 'note'> {
  const errors: Partial<Record<'productId' | 'quantity' | 'note', string>> = {}
  if (!input.productId) errors.productId = 'Pilih barang dari katalog.'
  const note = input.note.trim()
  if (charCount(note) > LIST_TEXT_LIMITS.note) errors.note = `Catatan maksimal ${LIST_TEXT_LIMITS.note} karakter.`
  const q = parseQuantityInput(input.quantityText, { allowFraction: input.allowFraction })
  if (!q.ok) errors.quantity = q.message
  if (Object.keys(errors).length > 0 || !q.ok) return { ok: false, errors }
  return { ok: true, value: { productId: input.productId, quantity: q.value, note: note === '' ? null : note } }
}
EOF

cat > "$B/sessionValidation.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import {
  parseActualQuantityInput,
  parseNeededQuantityInput,
  parsePriceActualInput,
  validateSessionCatalogForm,
  validateSessionManualForm,
} from './sessionValidation'

describe('parseActualQuantityInput', () => {
  it('menerima 0 dan pecahan sesuai snapshot', () => {
    expect(parseActualQuantityInput('0', { allowFraction: false })).toEqual({ ok: true, value: '0' })
    expect(parseActualQuantityInput('0,0', { allowFraction: true })).toEqual({ ok: true, value: '0' })
    expect(parseActualQuantityInput('0,25', { allowFraction: true })).toEqual({ ok: true, value: '0.25' })
    expect(parseActualQuantityInput('0,25', { allowFraction: false }).ok).toBe(false)
  })

  it('menolak kosong, negatif, bukan angka, dan lebih dari 3 desimal', () => {
    for (const bad of ['', '-1', 'abc', '0,0001', '1000000000']) {
      expect(parseActualQuantityInput(bad, { allowFraction: true }).ok).toBe(false)
    }
  })
})

describe('jumlah kebutuhan langsung', () => {
  it('harus lebih dari 0', () => {
    expect(parseNeededQuantityInput('0', { allowFraction: true }).ok).toBe(false)
    expect(parseNeededQuantityInput('3', { allowFraction: false })).toEqual({ ok: true, value: '3' })
  })
})

describe('parsePriceActualInput', () => {
  it('kosong mengosongkan, 0 sah, pecahan dan negatif ditolak', () => {
    expect(parsePriceActualInput('')).toEqual({ ok: true, value: null })
    expect(parsePriceActualInput('0')).toEqual({ ok: true, value: '0' })
    expect(parsePriceActualInput('Rp 12.500')).toEqual({ ok: true, value: '12500' })
    expect(parsePriceActualInput('12,5').ok).toBe(false)
    expect(parsePriceActualInput('-1').ok).toBe(false)
  })
})

describe('validateSessionCatalogForm', () => {
  const base = { productId: 'p1', quantityText: '2', note: '', allowFraction: false }

  it('batas catatan 1000 karakter (BR-039) dan catatan kosong menjadi null', () => {
    expect(validateSessionCatalogForm({ ...base, note: 'a'.repeat(1000) }).ok).toBe(true)
    expect(validateSessionCatalogForm({ ...base, note: 'a'.repeat(1001) }).ok).toBe(false)
    expect(validateSessionCatalogForm(base)).toEqual({ ok: true, value: { productId: 'p1', quantity: '2', note: null } })
  })

  it('mewajibkan barang dan menerapkan aturan pecahan', () => {
    expect(validateSessionCatalogForm({ ...base, productId: '' }).ok).toBe(false)
    expect(validateSessionCatalogForm({ ...base, quantityText: '0,5' }).ok).toBe(false)
    expect(validateSessionCatalogForm({ ...base, quantityText: '0,5', allowFraction: true }).ok).toBe(true)
  })
})

describe('validateSessionManualForm', () => {
  it('memakai batas yang sama dengan daftar', () => {
    const base = { name: 'Plastik', unit: 'pak', quantityText: '1,5', note: '' }
    expect(validateSessionManualForm(base).ok).toBe(true)
    expect(validateSessionManualForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
    expect(validateSessionManualForm({ ...base, unit: 'a'.repeat(51) }).ok).toBe(false)
  })
})
EOF

cat > "$B/sessionGuards.ts" <<'EOF'
export const OTHER_DEVICES_REMINDER =
  'Pastikan perangkat lain yang Anda pakai sudah menyinkronkan perubahannya. Aplikasi hanya dapat memeriksa perangkat ini.'

export interface StartPlan {
  allowed: boolean
  message: string
}

// FR-045: antrean perangkat pemulai harus kosong. Operasi yang ditolak server tidak menghalangi (SYNC-003).
export function planStart(blocking: number | null): StartPlan {
  if (blocking === null) {
    return {
      allowed: false,
      message:
        'Aplikasi tidak dapat memeriksa antrean perubahan di perangkat ini, jadi sesi belum dapat dimulai. Muat ulang halaman lalu coba lagi.',
    }
  }
  if (blocking > 0) {
    return {
      allowed: false,
      message: `Ada ${blocking} perubahan di perangkat ini yang belum tersimpan di server. Sesi tidak dapat dimulai sebelum perubahan itu tersimpan atau dibuang.`,
    }
  }
  return { allowed: true, message: OTHER_DEVICES_REMINDER }
}

export interface EndPlan {
  needsConfirm: boolean
  message: string
}

// FR-028, SYNC-012: perubahan yang belum tersimpan tidak ikut perhitungan sisa, total aktual, dan riwayat.
export function planEnd(pending: number | null): EndPlan {
  if (pending === null) {
    return {
      needsConfirm: true,
      message: `Aplikasi tidak dapat memeriksa perubahan yang belum tersimpan di server pada perangkat ini. Jika sesi tetap diakhiri, perubahan yang belum tersimpan tidak ikut dihitung. ${OTHER_DEVICES_REMINDER}`,
    }
  }
  if (pending > 0) {
    return {
      needsConfirm: true,
      message: `Ada ${pending} perubahan di perangkat ini yang belum tersimpan di server. Jika sesi tetap diakhiri, perubahan itu tidak ikut dihitung dalam sisa, total aktual, dan riwayat, lalu ditolak server dan ditandai gagal. ${OTHER_DEVICES_REMINDER}`,
    }
  }
  return { needsConfirm: false, message: OTHER_DEVICES_REMINDER }
}

async function safeCount(count: () => Promise<number>): Promise<number | null> {
  try {
    return await count()
  } catch {
    return null
  }
}

export async function checkStart(count: () => Promise<number>): Promise<StartPlan> {
  return planStart(await safeCount(count))
}

export async function checkEnd(count: () => Promise<number>): Promise<EndPlan> {
  return planEnd(await safeCount(count))
}
EOF

cat > "$B/sessionGuards.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { OTHER_DEVICES_REMINDER, checkEnd, checkStart, planEnd, planStart } from './sessionGuards'

describe('planStart (FR-045)', () => {
  it('antrean kosong boleh mulai dan mengingatkan perangkat lain tanpa menyatakan mereka sudah sinkron', () => {
    const p = planStart(0)
    expect(p.allowed).toBe(true)
    expect(p.message).toBe(OTHER_DEVICES_REMINDER)
    expect(p.message).not.toMatch(/sudah (tersinkron|tersimpan)/i)
  })

  it('operasi yang menghalangi membatalkan mulai dan menyebut belum tersimpan di server', () => {
    const p = planStart(3)
    expect(p.allowed).toBe(false)
    expect(p.message).toContain('3 perubahan')
    expect(p.message).toContain('belum tersimpan di server')
  })

  it('antrean tidak dapat diperiksa tidak boleh dianggap kosong', () => {
    expect(planStart(null).allowed).toBe(false)
  })
})

describe('planEnd (FR-028, SYNC-012)', () => {
  it('tanpa perubahan tertunda tidak perlu konfirmasi', () => {
    expect(planEnd(0).needsConfirm).toBe(false)
  })

  it('dengan perubahan tertunda wajib konfirmasi dan menjelaskan konsekuensinya', () => {
    const p = planEnd(2)
    expect(p.needsConfirm).toBe(true)
    expect(p.message).toContain('2 perubahan')
    expect(p.message).toContain('tidak ikut dihitung')
    expect(p.message).toContain('ditandai gagal')
  })

  it('tidak dapat diperiksa wajib konfirmasi', () => {
    expect(planEnd(null).needsConfirm).toBe(true)
  })
})

describe('checkStart dan checkEnd', () => {
  it('galat saat menghitung dianggap tidak dapat diperiksa', async () => {
    const boom = async (): Promise<number> => {
      throw new Error('dexie')
    }
    expect((await checkStart(boom)).allowed).toBe(false)
    expect((await checkEnd(boom)).needsConfirm).toBe(true)
  })

  it('memakai hasil hitung', async () => {
    expect((await checkStart(async () => 0)).allowed).toBe(true)
    expect((await checkEnd(async () => 4)).needsConfirm).toBe(true)
  })
})
EOF

cat > "$B/sessionGuardsLive.ts" <<'EOF'
import { countPendingOps } from '../../lib/pending-ops'
import { countBlockingOps } from '../../lib/queue'
import { checkEnd, checkStart } from './sessionGuards'

export const checkStartLive = () => checkStart(() => countBlockingOps())
export const checkEndLive = () => checkEnd(() => countPendingOps())
EOF

cat > "$B/syncFactory.ts" <<'EOF'
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { describeError, isOnline } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'

const sb = supabase as unknown as SupabaseClient

export interface SyncControllerConfig {
  channelPrefix: string
  tables: readonly string[]
  refresh: (workspaceId: string) => Promise<void>
  debounceMs?: number
}

// Refetch penuh berjeda, sama seperti katalog dan daftar. Satu langganan Realtime dipakai bersama.
export function createSyncController(cfg: SyncControllerConfig) {
  const debounce = cfg.debounceMs ?? 1500
  let state: SyncState = { status: 'idle', lastSyncedAt: null, error: null }
  const listeners = new Set<() => void>()
  let activeWorkspace: string | null = null
  let holders = 0
  let channel: RealtimeChannel | null = null
  let timer: ReturnType<typeof setTimeout> | undefined
  let running = false
  let rerun = false

  const setState = (patch: Partial<SyncState>) => {
    state = { ...state, ...patch }
    listeners.forEach((l) => l())
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
      await cfg.refresh(workspaceId)
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

  function schedule(delay: number = debounce) {
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
    let ch = sb.channel(`${cfg.channelPrefix}-${workspaceId}`)
    for (const table of cfg.tables) {
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

  return {
    getState: (): SyncState => state,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    acquire: (workspaceId: string): (() => void) => {
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
    },
    requestRefresh: () => schedule(0),
  }
}
EOF

cat > "$B/sessionStore.ts" <<'EOF'
import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import { toSessionItemRow, toSessionRow } from './rows'
import type { ServerSession, ServerSessionItem, SessionData, SessionRow } from './types'

const sb = supabase as unknown as SupabaseClient

export const SESSION_COLUMNS =
  'id, workspace_id, status, started_by, started_at, ended_by, ended_at, total_estimate, unpriced_items_at_start, total_actual, unpriced_items_purchased, created_at, updated_at'
export const SESSION_ITEM_COLUMNS =
  'id, session_id, workspace_id, source_item_id, product_id, product_name_snapshot, photo_path_snapshot, unit_snapshot, unit_id_snapshot, allow_fraction_snapshot, note_snapshot, price_snapshot, price_actual, quantity_needed, quantity_actual, status, deleted_at, created_at, updated_at'

const PAGE_SIZE = 1000

// Yang disimpan lokal: sesi aktif dan sesi berakhir terbaru. Riwayat penuh dibaca langsung dari server (Tahap 5).
async function fetchSessions(workspaceId: string): Promise<ServerSession[]> {
  const active = await sb
    .from('shopping_sessions')
    .select(SESSION_COLUMNS)
    .eq('workspace_id', workspaceId)
    .eq('status', 'active')
  if (active.error) throw active.error
  const ended = await sb
    .from('shopping_sessions')
    .select(SESSION_COLUMNS)
    .eq('workspace_id', workspaceId)
    .in('status', ['completed', 'cancelled'])
    .order('ended_at', { ascending: false, nullsFirst: false })
    .limit(1)
  if (ended.error) throw ended.error
  return [
    ...((active.data ?? []) as unknown as ServerSession[]),
    ...((ended.data ?? []) as unknown as ServerSession[]),
  ]
}

// Termasuk baris yang dihapus pengguna: perhitungan menyaringnya lewat deleted_at (FR-048).
async function fetchItems(workspaceId: string, sessionIds: string[]): Promise<ServerSessionItem[]> {
  if (sessionIds.length === 0) return []
  const rows: ServerSessionItem[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from('shopping_session_items')
      .select(SESSION_ITEM_COLUMNS)
      .eq('workspace_id', workspaceId)
      .in('session_id', sessionIds)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as ServerSessionItem[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Baris lokal yang tidak ikut hasil server (sesi lama, barang yang tidak lagi diambil) dibuang.
export async function refreshSessions(workspaceId: string): Promise<void> {
  const sessions = (await fetchSessions(workspaceId)).map(toSessionRow)
  const items = (await fetchItems(workspaceId, sessions.map((s: SessionRow) => s.id))).map(toSessionItemRow)
  const keepSessions = new Set(sessions.map((s) => s.id))
  const keepItems = new Set(items.map((i) => i.id))
  const db = getDb()
  await db.transaction('rw', db.sessions, db.sessionItems, async () => {
    const localSessions = await db.sessions.where('workspace_id').equals(workspaceId).primaryKeys()
    const staleSessions = localSessions.filter((id) => !keepSessions.has(id))
    if (staleSessions.length > 0) await db.sessions.bulkDelete(staleSessions)
    await db.sessions.bulkPut(sessions)

    const localItems = await db.sessionItems.where('workspace_id').equals(workspaceId).primaryKeys()
    const staleItems = localItems.filter((id) => !keepItems.has(id))
    if (staleItems.length > 0) await db.sessionItems.bulkDelete(staleItems)
    await db.sessionItems.bulkPut(items)
  })
}

export const sessionQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<SessionData> => {
    const db = getDb()
    return {
      sessions: await db.sessions.where('workspace_id').equals(workspaceId).toArray(),
      items: await db.sessionItems.where('workspace_id').equals(workspaceId).toArray(),
    }
  })

export async function clearSessionLocal(): Promise<void> {
  const db = getDb()
  await db.transaction('rw', db.sessions, db.sessionItems, async () => {
    await Promise.all([db.sessions.clear(), db.sessionItems.clear()])
  })
}
EOF

cat > "$B/sessionSync.ts" <<'EOF'
import { createSyncController } from './syncFactory'
import { refreshSessions } from './sessionStore'

const controller = createSyncController({
  channelPrefix: 'kps-session',
  tables: ['shopping_sessions', 'shopping_session_items'],
  refresh: refreshSessions,
})

export const getSessionSyncState = controller.getState
export const subscribeSessionSyncState = controller.subscribe
export const acquireSessionSync = controller.acquire
export const requestSessionRefresh = controller.requestRefresh
EOF

cat > "$B/useSessions.ts" <<'EOF'
import { useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { describeError } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { selectSessionState, type SessionState } from './sessionSelectors'
import { sessionQuery } from './sessionStore'
import {
  acquireSessionSync,
  getSessionSyncState,
  requestSessionRefresh,
  subscribeSessionSyncState,
} from './sessionSync'
import type { SessionData } from './types'

export function useSessionSyncState(): SyncState {
  return useSyncExternalStore(subscribeSessionSyncState, getSessionSyncState, getSessionSyncState)
}

// data bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useSessionData(workspaceId: string | null) {
  const [data, setData] = useState<SessionData | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setData(null)
      return undefined
    }
    const sub = sessionQuery(workspaceId).subscribe({
      next: (value) => {
        setData(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireSessionSync(workspaceId) : undefined), [workspaceId])

  return { data, readError, sync: useSessionSyncState(), refresh: requestSessionRefresh }
}

export function useSessionState(workspaceId: string | null) {
  const { data, readError, sync, refresh } = useSessionData(workspaceId)
  const state: SessionState | null = useMemo(() => (data ? selectSessionState(data) : null), [data])
  return { state, loading: state === null && readError === null, readError, sync, refresh }
}
EOF

cat > "$B/rpcDeps.ts" <<'EOF'
import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'

export const sbClient = supabase as unknown as SupabaseClient | null

export async function refreshSupabaseSession(): Promise<boolean> {
  if (!sbClient) return false
  const { data, error } = await sbClient.auth.refreshSession()
  return !error && data.session !== null
}
EOF

cat > "$B/submitSessionOp.ts" <<'EOF'
import type { SupabaseClient } from '@supabase/supabase-js'
import { requestListRefresh } from '../daftar/listSync'
import { createSubmitter, type SubmitOptions } from '../daftar/submitCore'
import type { ListOpResult } from '../daftar/types'
import { isOnline } from '../katalog/catalogStore'
import { refreshSupabaseSession, sbClient } from './rpcDeps'
import { sessionMessageForCode } from './sessionErrors'
import { toRpcCall, type SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'

export type SessionOpResult = ListOpResult

const core = createSubmitter({
  rpc: async (args) => {
    const call = toRpcCall(args)
    const res = await (sbClient as SupabaseClient).rpc(call.fn, call.args)
    return { data: res.data as unknown, error: res.error as unknown, status: res.status }
  },
  refreshSession: refreshSupabaseSession,
  isOnline,
  newId: () => crypto.randomUUID(),
  messageFor: sessionMessageForCode,
  offlineMessage: 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.',
})

const RETURNS_TO_LIST: readonly SessionOpType[] = ['kps_start_session', 'kps_end_session', 'kps_cancel_session']
const NO_REFRESH_CODES = ['OFFLINE', 'NO_CLIENT', 'SESSION_EXPIRED']

// Titik tunggal penulisan sesi. Antarmukanya sama dengan submitListOp; Tahap 6 mengganti isinya
// menjadi antrean offline untuk operasi yang boleh offline. Gunakan opId yang sama untuk kirim ulang.
export function submitSessionOp(
  workspaceId: string,
  opType: SessionOpType,
  payload: Record<string, unknown>,
  options: SubmitOptions = {},
): Promise<SessionOpResult> {
  if (!sbClient) {
    return Promise.resolve({
      ok: false,
      opId: options.opId ?? crypto.randomUUID(),
      code: 'NO_CLIENT',
      message: 'Supabase belum dikonfigurasi.',
      retryable: false,
    })
  }
  return core(workspaceId, opType, payload, options).then((r) => {
    if (r.ok) {
      requestSessionRefresh()
      // Mulai, akhiri, dan batalkan memindahkan barang antara daftar dan sesi.
      if (RETURNS_TO_LIST.includes(opType)) requestListRefresh()
    } else if (!r.retryable && !NO_REFRESH_CODES.includes(r.code)) {
      // Ditolak server: ambil keadaan terbaru supaya layar sama dengan server.
      requestSessionRefresh()
    }
    return r
  })
}
EOF

cat > "$B/submitGeneric.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { createAttemptRunner } from '../daftar/attemptRunner'
import { createSubmitter, type RpcReply, type SubmitDeps } from '../daftar/submitCore'
import { sessionMessageForCode } from './sessionErrors'
import { toRpcCall, type RpcCall } from './sessionRpc'

const accepted = (data: Record<string, unknown> = {}): RpcReply => ({
  data: { op_id: 'x', status: 'diterima', code: null, message: null, data, replayed: false },
  error: null,
  status: 200,
})
const rejected = (code: string): RpcReply => ({
  data: { op_id: 'x', status: 'ditolak', code, message: 'dari server', data: {}, replayed: false },
  error: null,
  status: 200,
})

function setup(replies: Array<RpcReply | Error>, over: Partial<SubmitDeps> = {}) {
  const calls: RpcCall[] = []
  const deps: SubmitDeps = {
    rpc: async (args) => {
      calls.push(toRpcCall(args))
      const next = replies.shift()
      if (!next) throw new Error('tidak ada balasan terjadwal')
      if (next instanceof Error) throw next
      return next
    },
    refreshSession: async () => true,
    isOnline: () => true,
    newId: () => 'op-1',
    messageFor: sessionMessageForCode,
    offlineMessage: 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.',
    ...over,
  }
  return { deps, calls }
}

describe('createSubmitter dengan operasi sesi', () => {
  it('mulai sesi dipanggil sebagai RPC sendiri dengan op_id dari submitter', async () => {
    const { deps, calls } = setup([accepted({ session_id: 's1', item_count: 3 })])
    const r = await createSubmitter(deps)('w1', 'kps_start_session', {})
    expect(r).toMatchObject({ ok: true, opId: 'op-1', data: { session_id: 's1', item_count: 3 } })
    expect(calls).toEqual([{ fn: 'kps_start_session', args: { p_workspace_id: 'w1', p_op_id: 'op-1' } }])
  })

  it('penolakan memakai pesan sesi', async () => {
    const a = await createSubmitter(setup([rejected('KPS_SESSION_NOT_ACTIVE')]).deps)('w1', 'session_set_status', {})
    expect(!a.ok && a.message).toContain('selesai atau dibatalkan')
    const b = await createSubmitter(setup([rejected('KPS_ITEM_DELETED')]).deps)('w1', 'session_set_status', {})
    expect(!b.ok && b.message).toContain('dihapus dari sesi')
    expect(!b.ok && b.retryable).toBe(false)
  })

  it('offline memakai pesan khusus dan tidak mengirim apa pun', async () => {
    const { deps, calls } = setup([], { isOnline: () => false })
    const r = await createSubmitter(deps)('w1', 'kps_start_session', {})
    expect(r).toMatchObject({ ok: false, code: 'OFFLINE' })
    expect(!r.ok && r.message).toContain('sesi belanja')
    expect(calls).toHaveLength(0)
  })
})

describe('createAttemptRunner dengan tipe operasi sesi', () => {
  it('mengakhiri sesi dikirim ulang dengan op_id dan session_id yang sama (SYNC-004)', async () => {
    const { deps, calls } = setup([new TypeError('Failed to fetch'), accepted({ session_id: 's1', returned_items: 2 })])
    const submit = createSubmitter(deps)
    const runner = createAttemptRunner((type, payload, options) => submit('w1', type, payload, options), () => 'op-r')

    const first = await runner.run('kps_end_session', { session_id: 's1' })
    expect(first).toMatchObject({ ok: false, code: 'NETWORK', retryable: true, opId: 'op-r' })
    expect(runner.hasPending()).toBe(true)

    const second = await runner.retry()
    expect(second).toMatchObject({ ok: true, opId: 'op-r' })
    expect(runner.hasPending()).toBe(false)
    expect(calls).toHaveLength(2)
    expect(calls[1]).toEqual(calls[0])
    expect(calls[0]).toEqual({
      fn: 'kps_end_session',
      args: { p_workspace_id: 'w1', p_op_id: 'op-r', p_session_id: 's1' },
    })
  })

  it('penolakan tidak menyisakan percobaan untuk dikirim ulang', async () => {
    const { deps } = setup([rejected('KPS_SESSION_ALREADY_ACTIVE')])
    const submit = createSubmitter(deps)
    const runner = createAttemptRunner((type, payload, options) => submit('w1', type, payload, options), () => 'op-r')
    const r = await runner.run('kps_start_session', {})
    expect(r).toMatchObject({ ok: false, code: 'KPS_SESSION_ALREADY_ACTIVE', retryable: false })
    expect(runner.hasPending()).toBe(false)
  })
})
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run && npm run build"