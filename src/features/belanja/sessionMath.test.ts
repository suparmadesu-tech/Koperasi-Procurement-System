import { describe, expect, it } from 'vitest'
import {
  actualTotals,
  effectivePriceOf,
  itemSubtotal,
  remainderOf,
  returnPreview,
  runningTotals,
  startTotals,
  statusCounts,
  type MathItem,
} from './sessionMath'

function it_(extra: Partial<MathItem>): MathItem {
  return {
    status: 'to_buy',
    price_actual: null,
    price_snapshot: null,
    quantity_actual: null,
    quantity_needed: '1',
    deleted_at: null,
    source_item_id: 's1',
    ...extra,
  }
}

describe('total berjalan dan total aktual', () => {
  const A = it_({ status: 'in_cart', price_snapshot: '3333', quantity_actual: '0.5' })
  const B = it_({ status: 'purchased', price_actual: '4000', quantity_actual: '3' })
  const C = it_({ status: 'to_buy', price_snapshot: '1000' })
  const D = it_({ status: 'purchased', quantity_actual: '1' })

  it('berjalan memuat in_cart dan purchased berharga, dibulatkan per barang menjauhi nol', () => {
    const t = runningTotals([A, B, C, D])
    expect(t.total).toBe('13667')
    expect(t.pricedCount).toBe(2)
    expect(t.unpricedCount).toBe(1)
    expect(t.incomplete).toBe(true)
  })

  it('aktual hanya purchased', () => {
    const t = actualTotals([A, B, C, D])
    expect(t.total).toBe('12000')
    expect(t.pricedCount).toBe(1)
    expect(t.unpricedCount).toBe(1)
  })

  it('to_buy tidak dihitung walau price_actual terisi', () => {
    const t = runningTotals([it_({ status: 'to_buy', price_actual: '5000' })])
    expect(t).toEqual({ total: '0', pricedCount: 0, unpricedCount: 0, incomplete: false })
  })

  it('barang yang dihapus tidak dihitung, termasuk sebagai barang tanpa harga (CK-11)', () => {
    const N = it_({ status: 'in_cart', price_snapshot: '2000', quantity_actual: '2', source_item_id: null })
    const R = it_({ status: 'purchased', price_snapshot: '900', quantity_actual: '1', source_item_id: null, deleted_at: 'x' })
    const U = it_({ status: 'purchased', quantity_actual: '1', source_item_id: null, deleted_at: 'x' })
    expect(runningTotals([N, R, U])).toEqual({ total: '4000', pricedCount: 1, unpricedCount: 0, incomplete: false })
    expect(actualTotals([N, R, U]).unpricedCount).toBe(0)
  })
})

describe('harga efektif', () => {
  it('price_actual menang atas snapshot dan dapat dikosongkan (CK-03)', () => {
    const base = { status: 'in_cart' as const, price_snapshot: '10000', quantity_actual: '2' }
    expect(itemSubtotal(it_({ ...base, price_actual: '11000' }))).toBe('22000')
    expect(itemSubtotal(it_({ ...base, price_actual: null }))).toBe('20000')
    expect(effectivePriceOf(it_({ ...base, price_actual: '11000' }))).toBe('11000')
  })

  it('price_actual 0 sah: barang berharga dengan subtotal 0 (CK-10)', () => {
    const k = it_({ status: 'purchased', price_snapshot: '9000', price_actual: '0', quantity_actual: '3' })
    expect(itemSubtotal(k)).toBe('0')
    expect(runningTotals([k])).toEqual({ total: '0', pricedCount: 1, unpricedCount: 0, incomplete: false })
  })

  it('tanpa jumlah aktual atau tanpa harga subtotalnya null, tidak pernah 0', () => {
    expect(itemSubtotal(it_({ status: 'to_buy', price_snapshot: '1000' }))).toBeNull()
    expect(itemSubtotal(it_({ status: 'in_cart', quantity_actual: '1' }))).toBeNull()
  })
})

describe('empat hitungan FR-050 tidak tercampur (CK-07)', () => {
  const P1 = it_({ status: 'purchased', price_actual: '2000', quantity_actual: '1', quantity_needed: '1' })
  const P2 = it_({ status: 'purchased', quantity_actual: '1', quantity_needed: '1' })
  const X = it_({ price_snapshot: '5000', quantity_needed: '2' })
  const direct = it_({ source_item_id: null, price_snapshot: '1000', quantity_needed: '5' })

  it('estimasi awal memakai snapshot dan hanya barang dari daftar', () => {
    expect(startTotals([P1, P2])).toEqual({ total: '0', pricedCount: 0, unpricedCount: 2, incomplete: true })
    expect(startTotals([X, direct, it_({ price_snapshot: '1', deleted_at: 'x' })])).toEqual({
      total: '10000',
      pricedCount: 1,
      unpricedCount: 0,
      incomplete: false,
    })
  })

  it('tanpa harga saat mulai berbeda dari tanpa harga yang dibeli', () => {
    expect(startTotals([P1, P2]).unpricedCount).toBe(2)
    expect(actualTotals([P1, P2]).unpricedCount).toBe(1)
  })
})

describe('sisa pengembalian (3.4.1)', () => {
  it('maks(0, dibutuhkan - terbeli) dan pecahan', () => {
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '10', quantity_actual: '8' }))).toBe('2')
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '10', quantity_actual: '12' }))).toBe('0')
    expect(remainderOf(it_({ status: 'in_cart', quantity_needed: '4', quantity_actual: '4' }))).toBe('4')
    expect(remainderOf(it_({ status: 'to_buy', quantity_needed: '5' }))).toBe('5')
    expect(remainderOf(it_({ status: 'purchased', quantity_needed: '0.5', quantity_actual: '0.25' }))).toBe('0.25')
  })

  it('pratinjau menghitung baris yang kembali dan melewatkan yang terpenuhi atau dihapus', () => {
    const items = [
      it_({ status: 'to_buy', quantity_needed: '5' }),
      it_({ status: 'purchased', quantity_needed: '3', quantity_actual: '3' }),
      it_({ status: 'to_buy', quantity_needed: '2', deleted_at: 'x', source_item_id: null }),
    ]
    expect(returnPreview(items)).toEqual({ count: 1 })
  })
})

describe('statusCounts', () => {
  it('menghitung hanya barang yang belum dihapus', () => {
    expect(
      statusCounts([
        it_({ status: 'to_buy' }),
        it_({ status: 'in_cart' }),
        it_({ status: 'purchased' }),
        it_({ status: 'purchased', deleted_at: 'x' }),
      ]),
    ).toEqual({ to_buy: 1, in_cart: 1, purchased: 1 })
  })
})
