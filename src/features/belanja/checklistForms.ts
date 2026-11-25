import { formatRupiah } from '../../lib/money'
import { formatQuantity } from '../daftar/format'
import { parseActualQuantityInput, parsePriceActualInput } from './sessionValidation'
import { STATUS_LABEL, type SessionItemView } from './sessionView'
import type { ItemStatus } from './types'

type QuantityItem = Pick<SessionItemView, 'status' | 'actual' | 'allowFraction'>
type PriceItem = Pick<SessionItemView, 'price' | 'priceIsActual'>

export type QuantityPlan = { kind: 'invalid'; message: string } | { kind: 'noop' } | { kind: 'send'; value: string }
export type PricePlan = { kind: 'invalid'; message: string } | { kind: 'noop' } | { kind: 'send'; value: string | null }

export const actualQuantityPrefill = (item: Pick<SessionItemView, 'actual'>): string =>
  item.actual === null ? '' : item.actual.replace('.', ',')

// Hanya harga aktual yang diisi ulang; harga awal sesi bukan nilai yang diubah pengguna (FR-053).
export const priceActualPrefill = (item: PriceItem): string =>
  item.priceIsActual && item.price !== null ? item.price : ''

// Jumlah aktual diisi hanya untuk in_cart atau purchased; server tetap penentu (KPS_QUANTITY_ACTUAL_STATE).
export function planActualQuantity(item: QuantityItem, text: string): QuantityPlan {
  if (item.status === 'to_buy') {
    return { kind: 'invalid', message: 'Jumlah aktual hanya dapat diisi untuk barang di keranjang atau sudah dibeli.' }
  }
  const q = parseActualQuantityInput(text, { allowFraction: item.allowFraction })
  if (!q.ok) return { kind: 'invalid', message: q.message }
  return q.value === item.actual ? { kind: 'noop' } : { kind: 'send', value: q.value }
}

// Kosong berarti mengosongkan (kirim null); 0 sah (FR-053).
export function planPriceActual(item: PriceItem, text: string): PricePlan {
  const p = parsePriceActualInput(text)
  if (!p.ok) return { kind: 'invalid', message: p.message }
  const current = item.priceIsActual ? item.price : null
  return p.value === current ? { kind: 'noop' } : { kind: 'send', value: p.value }
}

// Teks dipakai hanya setelah jawaban server diterima (SYNC-006).
export const statusOkText = (name: string, status: ItemStatus): string =>
  `${name}: status diubah menjadi ${STATUS_LABEL[status]} (dikonfirmasi server).`

export const quantityOkText = (name: string, value: string, unit: string): string =>
  `Jumlah aktual ${name} menjadi ${formatQuantity(value)}${unit ? ` ${unit}` : ''} (dikonfirmasi server).`

export const priceOkText = (name: string, value: string | null): string =>
  value === null
    ? `Harga aktual ${name} dikosongkan; memakai harga awal sesi (dikonfirmasi server).`
    : `Harga aktual ${name} menjadi ${formatRupiah(value)} (dikonfirmasi server).`
