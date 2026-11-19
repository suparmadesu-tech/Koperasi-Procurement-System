import { describe, expect, it } from 'vitest'
import { describeProduct, formatClock, pageSlice } from './viewModel'
import type { CategoryRow, ProductRow, UnitRow } from './types'

const base = { workspace_id: 'w', updated_at: '2026-11-18T00:00:00Z' }
const cat: CategoryRow = { ...base, id: 'c1', name: 'Sembako', is_archived: false }
const catOld: CategoryRow = { ...base, id: 'c2', name: 'Lama', is_archived: true }
const kg: UnitRow = { ...base, id: 'u1', name: 'kg', is_archived: false, allow_fraction: true }
const pcs: UnitRow = { ...base, id: 'u2', name: 'pcs', is_archived: true, allow_fraction: false }

const product = (patch: Partial<ProductRow>): ProductRow => ({
  ...base,
  id: 'p1',
  category_id: 'c1',
  unit_id: 'u1',
  name: 'Gula',
  photo_path: null,
  price: null,
  is_archived: false,
  ...patch,
})

const cats = new Map([cat, catOld].map((c) => [c.id, c]))
const units = new Map([kg, pcs].map((u) => [u.id, u]))

describe('describeProduct', () => {
  it('memuat kategori, satuan, dan harga terformat', () => {
    const v = describeProduct(product({ price: '12500' }), cats, units)
    expect(v.categoryName).toBe('Sembako')
    expect(v.unitName).toBe('kg')
    expect(v.allowFraction).toBe(true)
    expect(v.priceText).toContain('12.500')
  })
  it('harga kosong tidak menjadi nol, harga 0 tetap harga', () => {
    expect(describeProduct(product({ price: null }), cats, units).priceText).toBeNull()
    expect(describeProduct(product({ price: '0' }), cats, units).priceText).toContain('0')
  })
  it('menandai kategori dan satuan yang diarsipkan (FR-047)', () => {
    const v = describeProduct(product({ category_id: 'c2', unit_id: 'u2' }), cats, units)
    expect(v.categoryArchived).toBe(true)
    expect(v.unitArchived).toBe(true)
    expect(v.allowFraction).toBe(false)
  })
  it('rujukan yang belum ada di perangkat memakai teks cadangan', () => {
    const v = describeProduct(product({ category_id: 'x', unit_id: 'y' }), cats, units)
    expect(v.categoryName).toBe('Tanpa kategori')
    expect(v.unitName).toBe('Tanpa satuan')
    expect(v.allowFraction).toBeNull()
  })
})

describe('pageSlice', () => {
  it('memotong dan menghitung sisa', () => {
    expect(pageSlice([1, 2, 3, 4, 5], 2)).toEqual({ shown: [1, 2], remaining: 3 })
    expect(pageSlice([1, 2], 50)).toEqual({ shown: [1, 2], remaining: 0 })
    expect(pageSlice([], 50)).toEqual({ shown: [], remaining: 0 })
  })
})

describe('formatClock', () => {
  it('memakai zona waktu Asia/Jakarta', () => {
    expect(formatClock('2026-11-18T03:05:00Z')).toMatch(/10[.:]05/)
  })
})
