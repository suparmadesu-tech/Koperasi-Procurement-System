import { D, formatRupiah } from '../../lib/money'
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
    priceText: price === null ? null : formatRupiah(new D(price)),
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
