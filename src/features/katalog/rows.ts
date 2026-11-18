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
