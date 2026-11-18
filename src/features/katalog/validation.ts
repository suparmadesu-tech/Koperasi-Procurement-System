import { parsePriceInput } from './moneyAdapter'
import { TEXT_LIMITS } from './types'

export type FormResult<V, K extends string> =
  | { ok: true; value: V }
  | { ok: false; errors: Partial<Record<K, string>> }

// Panjang dihitung per code point, sama dengan char_length di PostgreSQL.
const charCount = (s: string) => Array.from(s).length

function checkName(raw: string, max: number, label: string): { value: string } | { error: string } {
  const value = raw.trim()
  if (value === '') return { error: `${label} wajib diisi.` }
  if (charCount(value) > max) return { error: `${label} maksimal ${max} karakter.` }
  return { value }
}

export function validateCategoryForm(input: { name: string }): FormResult<{ name: string }, 'name'> {
  const n = checkName(input.name, TEXT_LIMITS.categoryName, 'Nama kategori')
  if ('error' in n) return { ok: false, errors: { name: n.error } }
  return { ok: true, value: { name: n.value } }
}

export function validateUnitForm(input: {
  name: string
  allowFraction: boolean
}): FormResult<{ name: string; allow_fraction: boolean }, 'name'> {
  const n = checkName(input.name, TEXT_LIMITS.unitName, 'Nama satuan')
  if ('error' in n) return { ok: false, errors: { name: n.error } }
  return { ok: true, value: { name: n.value, allow_fraction: input.allowFraction } }
}

export interface ProductFormValue {
  name: string
  categoryId: string
  unitId: string
  price: string | null
}

export function validateProductForm(input: {
  name: string
  categoryId: string
  unitId: string
  priceText: string
}): FormResult<ProductFormValue, 'name' | 'categoryId' | 'unitId' | 'price'> {
  const errors: Partial<Record<'name' | 'categoryId' | 'unitId' | 'price', string>> = {}

  const n = checkName(input.name, TEXT_LIMITS.productName, 'Nama barang')
  if ('error' in n) errors.name = n.error
  if (!input.categoryId) errors.categoryId = 'Pilih kategori.'
  if (!input.unitId) errors.unitId = 'Pilih satuan.'
  const p = parsePriceInput(input.priceText)
  if (!p.ok) errors.price = p.message

  if ('error' in n || !p.ok || errors.categoryId || errors.unitId) return { ok: false, errors }
  return {
    ok: true,
    value: { name: n.value, categoryId: input.categoryId, unitId: input.unitId, price: p.value },
  }
}
