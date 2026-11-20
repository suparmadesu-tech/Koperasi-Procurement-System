import { describe, expect, it } from 'vitest'
import type { CatalogData, ProductRow } from '../katalog/types'
import { findHit, searchProducts } from './catalogSearch'

const p = (id: string, name: string, extra: Partial<ProductRow> = {}): ProductRow => ({
  id,
  workspace_id: 'w',
  category_id: 'c',
  unit_id: 'u-kg',
  name,
  photo_path: null,
  price: null,
  is_archived: false,
  updated_at: '',
  ...extra,
})

const data: CatalogData = {
  categories: [],
  units: [{ id: 'u-kg', workspace_id: 'w', name: 'kg', is_archived: false, updated_at: '', allow_fraction: true }],
  products: [p('1', 'Gula pasir', { price: '15000' }), p('2', 'Beras'), p('3', 'Gula merah', { is_archived: true }), p('4', 'gula aren')],
}

describe('searchProducts', () => {
  it('mengabaikan huruf besar kecil, membuang barang arsip, dan mengurutkan nama', () => {
    const r = searchProducts(data, ' GULA ', 10)
    expect(r.hits.map((h) => h.name)).toEqual(['gula aren', 'Gula pasir'])
    expect(r.total).toBe(2)
  })

  it('kueri kosong menampilkan semua barang aktif dan membatasi jumlah tampil', () => {
    const r = searchProducts(data, '', 2)
    expect(r.hits).toHaveLength(2)
    expect(r.total).toBe(3)
    expect(r.activeCount).toBe(3)
  })

  it('membawa satuan, aturan pecahan, dan harga', () => {
    const hit = searchProducts(data, 'pasir', 5).hits[0]
    expect(hit).toEqual({ id: '1', name: 'Gula pasir', unitName: 'kg', allowFraction: true, price: '15000' })
  })
})

describe('findHit', () => {
  it('tidak menemukan barang arsip atau yang tidak ada', () => {
    expect(findHit(data, '3')).toBeNull()
    expect(findHit(data, 'x')).toBeNull()
    expect(findHit(data, '2')?.name).toBe('Beras')
  })
})
