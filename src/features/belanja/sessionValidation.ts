import { LIST_TEXT_LIMITS } from '../daftar/types'
import { parseQuantityInput, type QuantityResult } from '../daftar/validation'
import type { FormResult } from '../katalog/validation'

// Harga aktual: kosong berarti mengosongkan (value null), 0 sah, Rupiah bulat (FR-053).
export { parsePriceInput as parsePriceActualInput } from '../katalog/moneyAdapter'
// Nama, satuan, jumlah, dan catatan barang manual di sesi memakai batas yang sama dengan daftar (BR-039).
export { validateManualItemForm as validateSessionManualForm } from '../daftar/validation'
// Jumlah kebutuhan barang yang ditambahkan langsung: lebih dari 0.
export { parseQuantityInput as parseNeededQuantityInput } from '../daftar/validation'

const charCount = (s: string) => Array.from(s).length

// Pecahan mengikuti allow_fraction_snapshot; server tetap penentu. Jumlah aktual 0 diterima (quantity_actual tidak negatif).
export function parseActualQuantityInput(text: string, opts: { allowFraction: boolean }): QuantityResult {
  const raw = text.trim().replace(',', '.')
  if (/^(0+(\.0*)?|\.0+)$/.test(raw)) return { ok: true, value: '0' }
  return parseQuantityInput(text, opts)
}

export function validateSessionCatalogForm(input: {
  productId: string
  quantityText: string
  note: string
  allowFraction: boolean
}): FormResult<{ productId: string; quantity: string; note: string | null }, 'productId' | 'quantity' | 'note'> {
  const errors: Partial<Record<'productId' | 'quantity' | 'note', string>> = {}
  if (!input.productId) errors.productId = 'Pilih barang dari katalog.'
  const note = input.note.trim()
  if (charCount(note) > LIST_TEXT_LIMITS.note) errors.note = `Catatan maksimal ${LIST_TEXT_LIMITS.note} karakter.`
  const q = parseQuantityInput(input.quantityText, { allowFraction: input.allowFraction })
  if (!q.ok) errors.quantity = q.message
  if (Object.keys(errors).length > 0 || !q.ok) return { ok: false, errors }
  return { ok: true, value: { productId: input.productId, quantity: q.value, note: note === '' ? null : note } }
}
