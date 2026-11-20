import { D } from '../../lib/money'
import type { FormResult } from '../katalog/validation'
import { LIST_TEXT_LIMITS } from './types'

// Panjang dihitung per code point, sama dengan char_length di PostgreSQL.
const charCount = (s: string) => Array.from(s).length
const MAX_QTY = new D('1000000000')

export type QuantityResult = { ok: true; value: string } | { ok: false; message: string }

// Koma dan titik sama-sama dianggap pemisah desimal. Pemisah ribuan tidak didukung.
export function parseQuantityInput(text: string, opts: { allowFraction: boolean }): QuantityResult {
  const raw = text.trim().replace(',', '.')
  if (raw === '') return { ok: false, message: 'Jumlah wajib diisi.' }
  if (!/^(\d+(\.\d+)?|\.\d+)$/.test(raw)) {
    return { ok: false, message: 'Jumlah harus berupa angka positif, misalnya 2 atau 1,5.' }
  }
  const d = new D(raw)
  if (d.decimalPlaces() > 3) return { ok: false, message: 'Jumlah maksimal 3 angka di belakang koma.' }
  if (d.lte(0)) return { ok: false, message: 'Jumlah harus lebih dari 0.' }
  if (d.gte(MAX_QTY)) return { ok: false, message: 'Jumlah terlalu besar.' }
  if (!opts.allowFraction && !d.isInteger()) {
    return { ok: false, message: 'Satuan ini tidak menerima jumlah berpecahan.' }
  }
  return { ok: true, value: d.toString() }
}

export function validateCatalogAddForm(input: {
  productId: string
  quantityText: string
  allowFraction: boolean
}): FormResult<{ productId: string; quantity: string }, 'productId' | 'quantity'> {
  const errors: Partial<Record<'productId' | 'quantity', string>> = {}
  if (!input.productId) errors.productId = 'Pilih barang dari katalog.'
  const q = parseQuantityInput(input.quantityText, { allowFraction: input.allowFraction })
  if (!q.ok) errors.quantity = q.message
  if (errors.productId || !q.ok) return { ok: false, errors }
  return { ok: true, value: { productId: input.productId, quantity: q.value } }
}

export interface ManualItemValue {
  name: string
  unit: string
  quantity: string
  note: string | null
}

type ManualKey = 'name' | 'unit' | 'quantity' | 'note'

export function validateManualItemForm(input: {
  name: string
  unit: string
  quantityText: string
  note: string
}): FormResult<ManualItemValue, ManualKey> {
  const errors: Partial<Record<ManualKey, string>> = {}
  const name = input.name.trim()
  const unit = input.unit.trim()
  const note = input.note.trim()
  const L = LIST_TEXT_LIMITS

  if (name === '') errors.name = 'Nama barang wajib diisi.'
  else if (charCount(name) > L.itemName) errors.name = `Nama barang maksimal ${L.itemName} karakter.`

  if (unit === '') errors.unit = 'Satuan wajib diisi.'
  else if (charCount(unit) > L.manualUnit) errors.unit = `Satuan maksimal ${L.manualUnit} karakter.`

  if (charCount(note) > L.note) errors.note = `Catatan maksimal ${L.note} karakter.`

  const q = parseQuantityInput(input.quantityText, { allowFraction: true })
  if (!q.ok) errors.quantity = q.message

  if (Object.keys(errors).length > 0 || !q.ok) return { ok: false, errors }
  return { ok: true, value: { name, unit, quantity: q.value, note: note === '' ? null : note } }
}
