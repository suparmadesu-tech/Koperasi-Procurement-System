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
