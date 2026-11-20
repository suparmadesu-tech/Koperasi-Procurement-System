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
