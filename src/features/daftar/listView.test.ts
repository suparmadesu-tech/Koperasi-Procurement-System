import { describe, expect, it } from 'vitest'
import type { CatalogData, ProductRow } from '../katalog/types'
import { buildListView, unpricedLabel } from './listView'
import type { ListItemRow } from './types'

const WS = 'w1'

function product(id: string, price: string | null, extra: Partial<ProductRow> = {}): ProductRow {
  return {
    id,
    workspace_id: WS,
    category_id: 'c1',
    unit_id: 'u-kg',
    name: id,
    photo_path: null,
    price,
    is_archived: false,
    updated_at: '',
    ...extra,
  }
}

const catalog = (products: ProductRow[]): CatalogData => ({
  categories: [],
  units: [
    { id: 'u-kg', workspace_id: WS, name: 'kg', is_archived: false, updated_at: '', allow_fraction: true },
    { id: 'u-pcs', workspace_id: WS, name: 'pcs', is_archived: false, updated_at: '', allow_fraction: false },
  ],
  products,
})

function item(id: string, extra: Partial<ListItemRow>): ListItemRow {
  return {
    id,
    workspace_id: WS,
    shopping_list_id: 'l1',
    product_id: null,
    manual_name: null,
    manual_unit: null,
    photo_path: null,
    note: null,
    quantity_needed: '1',
    created_at: '',
    updated_at: '',
    ...extra,
  }
}

describe('buildListView', () => {
  it('membulatkan subtotal per barang menjauhi nol dan menjumlah tanpa pembulatan ulang', () => {
    const v = buildListView(
      [
        item('i1', { product_id: 'p1', quantity_needed: '0.5' }),
        item('i2', { product_id: 'p2', quantity_needed: '2' }),
      ],
      catalog([product('p1', '3333'), product('p2', '1000')]),
    )
    const byId = Object.fromEntries(v.rows.map((r) => [r.id, r.subtotal]))
    expect(byId.i1).toBe('1667')
    expect(byId.i2).toBe('2000')
    expect(v.summary.total).toBe('3667')
    expect(v.summary.unpricedCount).toBe(0)
    expect(v.summary.incomplete).toBe(false)
  })

  it('barang manual dan katalog tanpa harga tidak dihitung nol dan menandai belum lengkap', () => {
    const v = buildListView(
      [
        item('i1', { product_id: 'p1', quantity_needed: '3' }),
        item('i2', { product_id: 'p2' }),
        item('i3', { manual_name: 'Plastik', manual_unit: 'pak', quantity_needed: '1.5' }),
      ],
      catalog([product('p1', '5000'), product('p2', null)]),
    )
    expect(v.summary.total).toBe('15000')
    expect(v.summary.pricedCount).toBe(1)
    expect(v.summary.unpricedCount).toBe(2)
    expect(v.summary.incomplete).toBe(true)
    expect(v.rows.find((r) => r.id === 'i2')?.subtotal).toBeNull()
    expect(v.rows.find((r) => r.id === 'i3')?.subtotal).toBeNull()
    expect(unpricedLabel(v.summary.unpricedCount)).toBe('Belum mencakup 2 barang tanpa harga')
  })

  it('tanpa satu pun barang berharga tetap ditandai belum lengkap', () => {
    const v = buildListView([item('i1', { manual_name: 'A', manual_unit: 'pcs' })], catalog([]))
    expect(v.summary.total).toBe('0')
    expect(v.summary.pricedCount).toBe(0)
    expect(v.summary.incomplete).toBe(true)
  })

  it('harga katalog 0 dianggap berharga', () => {
    const v = buildListView([item('i1', { product_id: 'p1', quantity_needed: '4' })], catalog([product('p1', '0')]))
    expect(v.rows[0]?.subtotal).toBe('0')
    expect(v.summary.unpricedCount).toBe(0)
  })

  it('produk yang belum ada di katalog lokal dihitung tanpa harga', () => {
    const v = buildListView([item('i1', { product_id: 'hilang' })], catalog([]))
    expect(v.rows[0]?.unresolved).toBe(true)
    expect(v.summary.unpricedCount).toBe(1)
  })

  it('membawa penanda arsip dan aturan pecahan dari satuan', () => {
    const v = buildListView(
      [item('i1', { product_id: 'p1' }), item('i2', { product_id: 'p2' })],
      catalog([product('p1', '100', { is_archived: true, unit_id: 'u-pcs' }), product('p2', '100')]),
    )
    const a = v.rows.find((r) => r.id === 'i1')
    const b = v.rows.find((r) => r.id === 'i2')
    expect(a?.archived).toBe(true)
    expect(a?.allowFraction).toBe(false)
    expect(a?.unitName).toBe('pcs')
    expect(b?.allowFraction).toBe(true)
  })

  it('mengurutkan berdasarkan nama', () => {
    const v = buildListView(
      [
        item('i1', { manual_name: 'Gula', manual_unit: 'kg' }),
        item('i2', { manual_name: 'Beras', manual_unit: 'kg' }),
      ],
      catalog([]),
    )
    expect(v.rows.map((r) => r.name)).toEqual(['Beras', 'Gula'])
  })
})
