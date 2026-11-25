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
  // allow_fraction_snapshot: pecahan jumlah aktual mengikuti snapshot (FR-012).
  allowFraction: boolean
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
    allowFraction: i.allow_fraction_snapshot,
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
