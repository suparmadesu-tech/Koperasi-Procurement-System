import { describe, expect, it } from 'vitest'
import { filterProducts, normalizeText, selectableOptions } from './search'
import type { ProductRow } from './types'

const p = (id: string, name: string, category_id = 'c1', is_archived = false): ProductRow => ({
  id,
  workspace_id: 'w',
  category_id,
  unit_id: 'u',
  name,
  photo_path: null,
  price: null,
  is_archived,
  updated_at: '2026-11-18T00:00:00Z',
})

const data = [
  p('1', 'Gula Pasir 1 kg'),
  p('2', 'Minyak Goreng 2 L', 'c2'),
  p('3', 'Café Susu', 'c2', true),
  p('4', 'beras premium 5 kg'),
]

describe('normalizeText', () => {
  it('menghapus diakritik, huruf besar, dan spasi ganda', () => {
    expect(normalizeText('  Café   SUSU ')).toBe('cafe susu')
  })
})

describe('filterProducts', () => {
  it('tanpa filter mengembalikan semua, terurut menurut nama', () => {
    expect(filterProducts(data).map((x) => x.id)).toEqual(['4', '3', '1', '2'])
  })
  it('mencocokkan semua kata di mana pun posisinya', () => {
    expect(filterProducts(data, { query: 'kg pasir' }).map((x) => x.id)).toEqual(['1'])
    expect(filterProducts(data, { query: 'cafe' }).map((x) => x.id)).toEqual(['3'])
  })
  it('menyaring kategori dan status arsip', () => {
    expect(filterProducts(data, { categoryId: 'c2' }).map((x) => x.id)).toEqual(['3', '2'])
    expect(filterProducts(data, { archive: 'active' }).map((x) => x.id)).not.toContain('3')
    expect(filterProducts(data, { archive: 'archived' }).map((x) => x.id)).toEqual(['3'])
  })
  it('query tanpa hasil memberi larik kosong', () => {
    expect(filterProducts(data, { query: 'tidak ada' })).toEqual([])
  })
})

describe('selectableOptions', () => {
  const rows = [
    { id: 'a', name: 'B', is_archived: false },
    { id: 'b', name: 'A', is_archived: true },
    { id: 'c', name: 'C', is_archived: true },
  ]
  it('hanya yang aktif untuk isian baru', () => {
    expect(selectableOptions(rows).map((r) => r.id)).toEqual(['a'])
  })
  it('mempertahankan nilai yang sedang dipakai walau diarsipkan', () => {
    expect(selectableOptions(rows, 'c').map((r) => r.id)).toEqual(['a', 'c'])
  })
})
