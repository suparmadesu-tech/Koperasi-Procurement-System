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
