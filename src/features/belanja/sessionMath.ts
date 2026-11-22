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
