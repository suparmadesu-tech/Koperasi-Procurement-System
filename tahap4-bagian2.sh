#!/usr/bin/env bash
# KPS Tahap 4, Bagian 2: layar baca sesi (hanya membaca, tanpa tulis ke tabel operasional).
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }
absent() { ! grep -qF -- "$2" "$1" || fail "$1 sudah memuat: $2"; }

B=src/features/belanja
D=src/features/daftar

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
command -v python3 >/dev/null || fail "python3 tidak ditemukan"
command -v node >/dev/null || fail "node tidak ditemukan"
[ -f package.json ] || fail "jalankan dari root repo (package.json tidak ada)"

for f in src/pages/Belanja.tsx src/components/Layout.tsx src/components/ui.ts src/lib/money.ts \
  src/auth/AuthProvider.tsx src/features/katalog/catalogSync.ts \
  "$D/format.ts" "$D/listView.ts" "$D/ListItemCard.tsx" "$D/ListSummaryCard.tsx" "$D/useList.ts" "$D/photoUrls.ts" \
  "$B/types.ts" "$B/sessionMath.ts" "$B/sessionSelectors.ts" "$B/useSessions.ts"; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
for f in format.ts format.test.ts sessionView.ts sessionView.test.ts SessionItemCard.tsx ActiveSession.tsx \
  CompletedSummary.tsx NoSessionView.tsx BelanjaView.tsx; do
  [ ! -e "$B/$f" ] || fail "$B/$f sudah ada; tidak ditimpa"
done

need src/components/Layout.tsx 'px-4 pb-28 pt-5'
need src/components/ui.ts 'export const btnSecondary'
need src/lib/money.ts 'export function formatRupiah('
need src/auth/AuthProvider.tsx 'workspace: { id: string; name: string };'
need src/auth/AuthProvider.tsx 'export function useAuth('
need src/features/katalog/catalogSync.ts 'export interface SyncState'
need "$D/format.ts" 'export function formatQuantity('
need "$D/format.ts" 'export function formatTimeJakarta('
need "$D/listView.ts" 'export const unpricedLabel'
need "$D/ListSummaryCard.tsx" 'export function ListSummaryCard'
need "$D/useList.ts" 'export function useDaftar('
need "$D/photoUrls.ts" 'export function usePhotoUrls('
need "$B/types.ts" 'export interface SessionRow'
need "$B/types.ts" 'export interface SessionItemRow'
need "$B/types.ts" 'export type ItemStatus'
need "$B/types.ts" 'export const ITEM_STATUSES'
need "$B/sessionMath.ts" 'export interface Totals'
need "$B/sessionMath.ts" 'export function runningTotals('
need "$B/sessionMath.ts" 'export function effectivePriceOf('
need "$B/sessionMath.ts" 'export function itemSubtotal('
need "$B/sessionMath.ts" 'export function statusCounts('
need "$B/sessionMath.ts" 'export function returnPreview('
need "$B/sessionMath.ts" 'export const isLiveItem'
need "$B/sessionSelectors.ts" 'export function selectSessionState('
need "$B/useSessions.ts" 'export function useSessionState('
absent src/pages/Belanja.tsx 'BelanjaView'
absent "$D/format.ts" 'hourCycle'
absent "$D/ListItemCard.tsx" 'export function ItemPhoto'

# Semua patch dicek dulu (tanpa menulis); diterapkan setelah berkas baru siap.
PATCHPY="$(mktemp)"
cat > "$PATCHPY" <<'PY'
import sys
check = len(sys.argv) > 1 and sys.argv[1] == "--check"

EDITS = {
  "src/pages/Belanja.tsx": [
    ("import Placeholder from './Placeholder';",
     "import { useAuth } from '../auth/AuthProvider';\nimport { BelanjaView } from '../features/belanja/BelanjaView';"),
    ('  return <Placeholder title="Belanja" note="Sesi belanja belum tersedia. Dibuat di Tahap 4." />;',
     "  const { state } = useAuth();\n  if (state.status !== 'ready') return null;\n  return <BelanjaView workspaceId={state.workspace.id} />;"),
  ],
  "src/features/daftar/format.ts": [
    ("    timeZone: 'Asia/Jakarta',",
     "    hourCycle: 'h23',\n    timeZone: 'Asia/Jakarta',"),
  ],
  "src/features/daftar/ListItemCard.tsx": [
    ("function ItemPhoto({ url, name }: { url: string | undefined; name: string }) {",
     "export function ItemPhoto({ url, name }: { url: string | undefined; name: string }) {"),
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
python3 "$PATCHPY" --check || { rm -f "$PATCHPY"; exit 1; }

# --- Penulisan berkas baru ---
cat > "$B/format.ts" <<'EOF'
// Tanggal dan jam Asia/Jakarta dengan jam 24 (FR-039).
export function formatDateTimeJakarta(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '-'
  return new Intl.DateTimeFormat('id-ID', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'Asia/Jakarta',
  }).format(d)
}
EOF

cat > "$B/format.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { formatTimeJakarta } from '../daftar/format'
import { formatDateTimeJakarta } from './format'

describe('jam 24 Asia/Jakarta', () => {
  it('tengah malam tampil 00, bukan 24', () => {
    expect(formatTimeJakarta('2026-11-20T17:05:00Z')).toMatch(/^00[.:]05$/)
    expect(formatDateTimeJakarta('2026-11-20T17:05:00Z')).toMatch(/\b00[.:]05\b/)
    expect(formatDateTimeJakarta('2026-11-20T17:05:00Z')).not.toMatch(/24[.:]05/)
  })

  it('siang tetap 14.32 dan tanggal Jakarta ikut tampil', () => {
    const s = formatDateTimeJakarta('2026-11-20T07:32:00Z')
    expect(s).toMatch(/14[.:]32/)
    expect(s).toMatch(/20/)
    expect(s).toMatch(/2026/)
  })

  it('tanggal tidak valid tidak melempar galat', () => {
    expect(formatDateTimeJakarta('bukan tanggal')).toBe('-')
  })
})
EOF

cat > "$B/sessionView.ts" <<'EOF'
import {
  effectivePriceOf,
  isLiveItem,
  itemSubtotal,
  returnPreview,
  runningTotals,
  statusCounts,
  type Totals,
} from './sessionMath'
import { ITEM_STATUSES, type ItemStatus, type SessionItemRow, type SessionRow } from './types'

export const STATUS_LABEL: Record<ItemStatus, string> = {
  to_buy: 'Belum dibeli',
  in_cart: 'Di keranjang',
  purchased: 'Sudah dibeli',
}

export interface SessionItemView {
  id: string
  name: string
  unitName: string
  status: ItemStatus
  needed: string
  actual: string | null
  // Harga efektif (FR-053); null berarti tanpa harga dan tidak pernah tampil Rp 0 (FR-019).
  price: string | null
  priceIsActual: boolean
  subtotal: string | null
  note: string | null
  photoPath: string | null
  // Ditambahkan langsung ke sesi (source_item_id kosong, FR-052).
  direct: boolean
}

export interface StatusGroup {
  status: ItemStatus
  label: string
  items: SessionItemView[]
}

// Nilai beku dari server, tidak dihitung ulang di klien (FR-024, FR-050).
export interface FrozenStart {
  total: string | null
  unpricedCount: number | null
}

export interface ActiveView {
  startedAt: string
  itemCount: number
  groups: StatusGroup[]
  running: Totals
  frozen: FrozenStart
}

export interface CompletedView {
  endedAt: string | null
  totalActual: string | null
  unpricedPurchased: number | null
  estimate: FrozenStart
  purchasedCount: number
  returnCount: number
}

const byName = (a: SessionItemRow, b: SessionItemRow) =>
  a.product_name_snapshot.localeCompare(b.product_name_snapshot, 'id') || a.id.localeCompare(b.id)

function toItemView(i: SessionItemRow): SessionItemView {
  return {
    id: i.id,
    name: i.product_name_snapshot,
    unitName: i.unit_snapshot,
    status: i.status,
    needed: i.quantity_needed,
    actual: i.quantity_actual,
    price: effectivePriceOf(i),
    priceIsActual: i.price_actual !== null,
    subtotal: itemSubtotal(i),
    note: i.note_snapshot,
    photoPath: i.photo_path_snapshot,
    direct: i.source_item_id === null,
  }
}

export function buildActiveView(session: SessionRow, items: SessionItemRow[]): ActiveView {
  const live = items.filter(isLiveItem).sort(byName)
  const groups = ITEM_STATUSES.map((status) => ({
    status,
    label: STATUS_LABEL[status],
    items: live.filter((i) => i.status === status).map(toItemView),
  })).filter((g) => g.items.length > 0)

  return {
    startedAt: session.started_at,
    itemCount: live.length,
    groups,
    running: runningTotals(live),
    frozen: { total: session.total_estimate, unpricedCount: session.unpriced_items_at_start },
  }
}

// Hanya sesi completed yang punya ringkasan; sesi cancelled tidak punya layar sendiri (FR-040).
export function buildCompletedView(session: SessionRow | null, items: SessionItemRow[]): CompletedView | null {
  if (session === null || session.status !== 'completed') return null
  const live = items.filter(isLiveItem)
  return {
    endedAt: session.ended_at,
    totalActual: session.total_actual,
    unpricedPurchased: session.unpriced_items_purchased,
    estimate: { total: session.total_estimate, unpricedCount: session.unpriced_items_at_start },
    purchasedCount: statusCounts(live).purchased,
    returnCount: returnPreview(live).count,
  }
}
EOF

cat > "$B/sessionView.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { buildActiveView, buildCompletedView } from './sessionView'
import type { SessionItemRow, SessionRow } from './types'

const session = (extra: Partial<SessionRow> = {}): SessionRow => ({
  id: 's', workspace_id: 'w', status: 'active', started_by: null, started_at: '2026-11-20T07:00:00Z',
  ended_by: null, ended_at: null, total_estimate: '99999', unpriced_items_at_start: 7, total_actual: null,
  unpriced_items_purchased: null, created_at: '', updated_at: '', ...extra,
})

const item = (id: string, extra: Partial<SessionItemRow> = {}): SessionItemRow => ({
  id, session_id: 's', workspace_id: 'w', source_item_id: 'src', product_id: null, product_name_snapshot: id,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: null, price_actual: null, quantity_needed: '1', quantity_actual: null,
  status: 'to_buy', deleted_at: null, created_at: '', updated_at: '', ...extra,
})

describe('buildActiveView', () => {
  it('estimasi awal dan jumlah tanpa harga awal diambil dari nilai beku server, bukan dihitung ulang', () => {
    const v = buildActiveView(session(), [item('a', { price_snapshot: '1000', quantity_needed: '5' })])
    expect(v.frozen).toEqual({ total: '99999', unpricedCount: 7 })
  })

  it('total berjalan dihitung dari barang, terpisah dari nilai beku (FR-050)', () => {
    const v = buildActiveView(session(), [
      item('a', { status: 'in_cart', price_snapshot: '1000', quantity_actual: '2' }),
      item('b', { status: 'purchased', quantity_actual: '1' }),
    ])
    expect(v.running).toEqual({ total: '2000', pricedCount: 1, unpricedCount: 1, incomplete: true })
    expect(v.frozen.unpricedCount).toBe(7)
  })

  it('mengelompokkan per status berurutan, membuang kelompok kosong dan barang yang dihapus', () => {
    const v = buildActiveView(session(), [
      item('c', { status: 'purchased', quantity_actual: '1' }),
      item('a', { status: 'to_buy' }),
      item('b', { status: 'in_cart', quantity_actual: '1' }),
      item('d', { status: 'to_buy', source_item_id: null, deleted_at: '2026-11-20T08:00:00Z' }),
    ])
    expect(v.groups.map((g) => g.status)).toEqual(['to_buy', 'in_cart', 'purchased'])
    expect(v.itemCount).toBe(3)
    expect(v.groups.flatMap((g) => g.items.map((i) => i.id))).toEqual(['a', 'b', 'c'])
    expect(buildActiveView(session(), [item('x')]).groups.map((g) => g.status)).toEqual(['to_buy'])
    expect(buildActiveView(session(), []).groups).toEqual([])
  })

  it('harga efektif: aktual menang, 0 sah, tanpa harga tetap null', () => {
    const v = buildActiveView(session(), [
      item('a', { status: 'in_cart', price_snapshot: '10000', price_actual: '11000', quantity_actual: '2' }),
      item('b', { status: 'in_cart', price_snapshot: '10000', quantity_actual: '2' }),
      item('c', { status: 'in_cart', price_snapshot: '9000', price_actual: '0', quantity_actual: '3' }),
      item('d', { status: 'in_cart', quantity_actual: '1' }),
    ])
    const by = Object.fromEntries(v.groups[0]!.items.map((i) => [i.id, i]))
    expect(by.a).toMatchObject({ price: '11000', priceIsActual: true, subtotal: '22000' })
    expect(by.b).toMatchObject({ price: '10000', priceIsActual: false, subtotal: '20000' })
    expect(by.c).toMatchObject({ price: '0', priceIsActual: true, subtotal: '0' })
    expect(by.d).toMatchObject({ price: null, subtotal: null })
  })

  it('barang to_buy tidak punya subtotal walau berharga, dan penanda langsung terbaca', () => {
    const v = buildActiveView(session(), [item('a', { price_snapshot: '5000' }), item('b', { source_item_id: null })])
    const by = Object.fromEntries(v.groups[0]!.items.map((i) => [i.id, i]))
    expect(by.a).toMatchObject({ price: '5000', subtotal: null, direct: false })
    expect(by.b?.direct).toBe(true)
  })
})

describe('buildCompletedView', () => {
  it('hanya sesi completed yang punya ringkasan (FR-040)', () => {
    expect(buildCompletedView(null, [])).toBeNull()
    expect(buildCompletedView(session({ status: 'active' }), [])).toBeNull()
    expect(buildCompletedView(session({ status: 'cancelled', ended_at: '2026-11-20T09:00:00Z' }), [])).toBeNull()
  })

  it('total aktual dan jumlah tanpa harga dibeli diambil dari nilai beku server', () => {
    const s = session({
      status: 'completed', ended_at: '2026-11-20T09:00:00Z', total_actual: '12000', unpriced_items_purchased: 1,
    })
    const v = buildCompletedView(s, [
      item('p1', { status: 'purchased', price_actual: '2000', quantity_actual: '1', quantity_needed: '3' }),
      item('p2', { status: 'purchased', quantity_actual: '1' }),
      item('x', { status: 'to_buy', quantity_needed: '2' }),
      item('r', { status: 'to_buy', source_item_id: null, deleted_at: '2026-11-20T08:00:00Z' }),
    ])
    expect(v).toEqual({
      endedAt: '2026-11-20T09:00:00Z',
      totalActual: '12000',
      unpricedPurchased: 1,
      estimate: { total: '99999', unpricedCount: 7 },
      purchasedCount: 2,
      returnCount: 2,
    })
  })
})
EOF

cat > "$B/SessionItemCard.tsx" <<'EOF'
import { formatRupiah } from '../../lib/money'
import { formatQuantity } from '../daftar/format'
import { ItemPhoto } from '../daftar/ListItemCard'
import type { SessionItemView } from './sessionView'

export function SessionItemCard({ item, photoUrl }: { item: SessionItemView; photoUrl: string | undefined }) {
  const unit = item.unitName ? ` ${item.unitName}` : ''
  return (
    <li className="flex gap-3 rounded-md bg-white p-3 ring-1 ring-black/20">
      {item.photoPath ? <ItemPhoto key={photoUrl ?? 'tanpa-url'} url={photoUrl} name={item.name} /> : null}
      <div className="min-w-0 flex-1 space-y-1">
        <p className="break-words font-semibold">{item.name}</p>
        <p className="text-sm">
          Dibutuhkan {formatQuantity(item.needed)}
          {unit}
          {item.actual !== null ? ` · Aktual ${formatQuantity(item.actual)}${unit}` : ''}
        </p>
        {item.note ? <p className="whitespace-pre-line break-words text-sm">Catatan: {item.note}</p> : null}
        {item.price === null ? (
          <p className="text-sm">Harga belum tersedia</p>
        ) : (
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
            <span>
              {formatRupiah(item.price)} {item.priceIsActual ? '(harga aktual)' : '(harga awal sesi)'}
            </span>
            {item.subtotal !== null ? (
              <span className="font-semibold">{formatRupiah(item.subtotal)}</span>
            ) : (
              <span className="text-xs text-ink/75">Belum masuk total</span>
            )}
          </div>
        )}
        {item.direct ? <p className="text-xs text-ink/75">Ditambahkan langsung ke sesi</p> : null}
      </div>
    </li>
  )
}
EOF

cat > "$B/ActiveSession.tsx" <<'EOF'
import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'
import { formatDateTimeJakarta } from './format'
import { SessionItemCard } from './SessionItemCard'
import type { ActiveView } from './sessionView'

export function ActiveSession({ view, photoUrls }: { view: ActiveView; photoUrls: Record<string, string> }) {
  const { running, frozen } = view
  const runningEmpty = running.pricedCount + running.unpricedCount === 0
  return (
    <div className="space-y-4">
      <section aria-labelledby="ringkasan-sesi" className="space-y-4 rounded-md bg-white p-4 ring-1 ring-black/20">
        <div>
          <h2 id="ringkasan-sesi" className="font-semibold">
            Sesi belanja aktif
          </h2>
          <p className="text-sm text-ink/75">Dimulai {formatDateTimeJakarta(view.startedAt)} WIB</p>
        </div>
        <dl className="space-y-4">
          <div className="space-y-1">
            <dt className="text-sm text-ink/75">Total berjalan (barang di keranjang dan sudah dibeli)</dt>
            <dd className="text-2xl font-semibold">{formatRupiah(running.total)}</dd>
            {running.incomplete ? (
              <dd className="text-sm">
                <span className="font-semibold">Total berjalan belum lengkap.</span> {unpricedLabel(running.unpricedCount)}.
              </dd>
            ) : null}
            {runningEmpty ? <dd className="text-sm">Belum ada barang di keranjang.</dd> : null}
            <dd className="text-xs text-ink/75">Memakai harga aktual bila diisi, jika tidak harga awal sesi.</dd>
          </div>
          <div className="space-y-1">
            <dt className="text-sm text-ink/75">Estimasi awal (dibekukan saat sesi dimulai)</dt>
            <dd className="text-lg font-semibold">
              {frozen.total === null ? 'Belum tersedia' : formatRupiah(frozen.total)}
            </dd>
            {frozen.unpricedCount !== null && frozen.unpricedCount > 0 ? (
              <dd className="text-sm">{unpricedLabel(frozen.unpricedCount)}.</dd>
            ) : null}
            <dd className="text-xs text-ink/75">
              Tidak berubah walau harga katalog diperbarui atau barang ditambahkan ke sesi.
            </dd>
          </div>
        </dl>
      </section>

      {view.itemCount === 0 ? (
        <p className="text-sm">Sesi ini belum memiliki barang.</p>
      ) : (
        view.groups.map((g) => (
          <section key={g.status} aria-labelledby={`grup-${g.status}`} className="space-y-3">
            <h2 id={`grup-${g.status}`} className="font-semibold">
              {g.label} ({g.items.length})
            </h2>
            <ul className="space-y-3">
              {g.items.map((i) => (
                <SessionItemCard key={i.id} item={i} photoUrl={i.photoPath ? photoUrls[i.photoPath] : undefined} />
              ))}
            </ul>
          </section>
        ))
      )}
    </div>
  )
}
EOF

cat > "$B/CompletedSummary.tsx" <<'EOF'
import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'
import { formatDateTimeJakarta } from './format'
import type { CompletedView } from './sessionView'

export function CompletedSummary({ view }: { view: CompletedView }) {
  const { estimate } = view
  return (
    <section aria-labelledby="ringkasan-selesai" className="space-y-4 rounded-md bg-white p-4 ring-1 ring-black/20">
      <div>
        <h2 id="ringkasan-selesai" className="font-semibold">
          Sesi belanja terakhir selesai
        </h2>
        {view.endedAt ? <p className="text-sm text-ink/75">Selesai {formatDateTimeJakarta(view.endedAt)} WIB</p> : null}
      </div>
      <dl className="space-y-4">
        <div className="space-y-1">
          <dt className="text-sm text-ink/75">Total aktual (barang yang dibeli)</dt>
          <dd className="text-2xl font-semibold">
            {view.totalActual === null ? 'Tidak tersedia' : formatRupiah(view.totalActual)}
          </dd>
          {view.unpricedPurchased === null ? (
            <dd className="text-sm">Jumlah barang tanpa harga tidak tersedia.</dd>
          ) : view.unpricedPurchased > 0 ? (
            <dd className="text-sm">{unpricedLabel(view.unpricedPurchased)}.</dd>
          ) : null}
        </div>
        <div className="space-y-1">
          <dt className="text-sm text-ink/75">Estimasi awal (saat sesi dimulai)</dt>
          <dd className="text-lg font-semibold">
            {estimate.total === null ? 'Tidak tersedia' : formatRupiah(estimate.total)}
          </dd>
          {estimate.unpricedCount !== null && estimate.unpricedCount > 0 ? (
            <dd className="text-sm">{unpricedLabel(estimate.unpricedCount)}.</dd>
          ) : null}
        </div>
      </dl>
      <p className="text-sm">
        {view.purchasedCount} barang dibeli. {view.returnCount} barang memiliki sisa yang dikembalikan ke daftar
        kebutuhan.
      </p>
    </section>
  )
}
EOF

cat > "$B/NoSessionView.tsx" <<'EOF'
import { ListSummaryCard } from '../daftar/ListSummaryCard'
import { useDaftar } from '../daftar/useList'
import { CompletedSummary } from './CompletedSummary'
import type { CompletedView } from './sessionView'

// Dipasang hanya saat tidak ada sesi aktif, jadi langganan daftar dan katalog hanya hidup di keadaan ini.
export function NoSessionView({ workspaceId, completed }: { workspaceId: string; completed: CompletedView | null }) {
  const { view, readError, catalogSync } = useDaftar(workspaceId)
  const catalogPending = view !== null && view.rows.some((r) => r.unresolved) && catalogSync.status !== 'ok'

  return (
    <div className="space-y-4">
      {completed ? <CompletedSummary view={completed} /> : null}
      <section aria-labelledby="status-sesi" className="space-y-3">
        <h2 id="status-sesi" className="font-semibold">
          Belum ada sesi belanja yang aktif
        </h2>
        <p className="text-sm">Ringkasan daftar kebutuhan saat ini:</p>
        {readError !== null ? (
          <p role="alert" className="text-sm text-red-900">
            Daftar tidak dapat dibaca dari perangkat: {readError}
          </p>
        ) : view === null ? (
          <p role="status" className="text-sm">
            Membaca daftar dari perangkat...
          </p>
        ) : view.rows.length === 0 ? (
          <p className="text-sm">Daftar kebutuhan masih kosong.</p>
        ) : (
          <>
            {catalogPending ? (
              <p role="status" className="text-sm">
                Katalog belum termuat di perangkat, jadi sebagian harga belum dapat dihitung.
              </p>
            ) : null}
            <ListSummaryCard summary={view.summary} />
          </>
        )}
      </section>
    </div>
  )
}
EOF

cat > "$B/BelanjaView.tsx" <<'EOF'
import { useMemo, type ReactNode } from 'react'
import { btnSecondary } from '../../components/ui'
import { formatTimeJakarta } from '../daftar/format'
import { usePhotoUrls } from '../daftar/photoUrls'
import type { SyncState } from '../katalog/catalogSync'
import { ActiveSession } from './ActiveSession'
import { NoSessionView } from './NoSessionView'
import { buildActiveView, buildCompletedView } from './sessionView'
import { useSessionState } from './useSessions'

function Notice({ alert, children }: { alert?: boolean; children: ReactNode }) {
  const tone = alert ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
  return (
    <div role={alert ? 'alert' : 'status'} className={`rounded-md bg-white p-3 text-sm ring-1 ${tone}`}>
      {children}
    </div>
  )
}

function syncLabel(sync: SyncState): string | null {
  if (sync.status === 'syncing') return 'Menyegarkan dari server...'
  if (sync.status === 'ok' && sync.lastSyncedAt) return `Data dari server pukul ${formatTimeJakarta(sync.lastSyncedAt)} WIB`
  return null
}

export function BelanjaView({ workspaceId }: { workspaceId: string }) {
  const { state, readError, sync, refresh } = useSessionState(workspaceId)

  const activeView = useMemo(
    () => (state && state.active ? buildActiveView(state.active, state.activeItems) : null),
    [state],
  )
  const completed = useMemo(() => (state ? buildCompletedView(state.lastEnded, state.lastEndedItems) : null), [state])
  const photoPaths = useMemo(
    () =>
      activeView
        ? activeView.groups.flatMap((g) => g.items.flatMap((i) => (i.photoPath ? [i.photoPath] : [])))
        : [],
    [activeView],
  )
  const photoUrls = usePhotoUrls(photoPaths, sync.lastSyncedAt)

  const label = syncLabel(sync)
  const busy = sync.status === 'syncing'
  // Tanpa data lokal dan sinkronisasi pertama belum selesai, "tanpa sesi" belum boleh disimpulkan.
  const checking =
    state !== null &&
    state.active === null &&
    sync.lastSyncedAt === null &&
    (sync.status === 'idle' || sync.status === 'syncing')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold">Belanja</h1>
          {label ? <p className="text-sm text-ink/75">{label}</p> : null}
          <p className="text-xs text-ink/75">
            Perubahan dari perangkat lain tampil setelah data disegarkan. Layar ini tidak dapat memastikan perangkat
            lain sudah tersinkron.
          </p>
        </div>
        <button
          type="button"
          className={btnSecondary}
          onClick={refresh}
          disabled={busy || sync.status === 'offline'}
        >
          {busy ? 'Memuat...' : 'Muat ulang'}
        </button>
      </div>

      {readError !== null ? (
        <Notice alert>
          <p>Data sesi tidak dapat dibaca dari penyimpanan perangkat: {readError}</p>
          <button type="button" className={`${btnSecondary} mt-3`} onClick={() => window.location.reload()}>
            Muat ulang halaman
          </button>
        </Notice>
      ) : state === null ? (
        <p role="status">Membaca data sesi dari perangkat...</p>
      ) : (
        <>
          {sync.status === 'offline' ? (
            <Notice>
              Anda sedang offline. Layar menampilkan data sesi yang terakhir tersimpan di perangkat. Sesi di server
              mungkin sudah berubah.
            </Notice>
          ) : null}
          {sync.status === 'error' ? (
            <Notice alert>
              Data sesi belum dapat disegarkan dari server. Menampilkan data terakhir di perangkat.
              {sync.error ? <span className="mt-1 block break-words text-xs">Rincian: {sync.error}</span> : null}
            </Notice>
          ) : null}
          {checking ? (
            <p role="status">Memeriksa sesi belanja di server...</p>
          ) : activeView ? (
            <ActiveSession view={activeView} photoUrls={photoUrls} />
          ) : (
            <NoSessionView workspaceId={workspaceId} completed={completed} />
          )}
        </>
      )}
    </div>
  )
}
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run && npm run build"
