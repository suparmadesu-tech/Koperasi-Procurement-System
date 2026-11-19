import type { ProductPatch } from './rows'
import type { ProductRow } from './types'
import type { ProductFormValue } from './validation'

const normalizePrice = (p: string | null) => (p === null ? null : p.replace(/\.0+$/, ''))

// Hanya kolom yang berubah yang dikirim, supaya UPDATE tidak menyentuh kolom lain.
export function diffProduct(current: ProductRow, next: ProductFormValue, archived: boolean): ProductPatch {
  const patch: ProductPatch = {}
  if (next.name !== current.name) patch.name = next.name
  if (next.categoryId !== current.category_id) patch.categoryId = next.categoryId
  if (next.unitId !== current.unit_id) patch.unitId = next.unitId
  if (normalizePrice(next.price) !== normalizePrice(current.price)) patch.price = next.price
  if (archived !== current.is_archived) patch.isArchived = archived
  return patch
}
