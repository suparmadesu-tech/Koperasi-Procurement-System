import { describe, expect, it } from 'vitest'
import { buildActiveView, buildCompletedView } from './sessionView'
import type { SessionItemRow, SessionRow } from './types'

const session = (extra: Partial<SessionRow> = {}): SessionRow => ({
  id: 's', workspace_id: 'w', status: 'active', started_by: null, started_at: '2026-11-20T07:00:00Z',
  ended_by: null, ended_at: null, total_estimate: '99999', unpriced_items_at_start: 7, total_actual: null,
  unpriced_items_purchased: null, created_at: '', updated_at: '', ...extra,
})

const item = (id: string, extra: Partial<SessionItemRow> = {}): SessionItemRow => ({
  id, session_id: 's', workspace_id: 'w', source_item_id: 'src', product_id: null, product_name_snapshot: id,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: null, price_actual: null, quantity_needed: '1', quantity_actual: null,
  status: 'to_buy', deleted_at: null, created_at: '', updated_at: '', ...extra,
})

describe('buildActiveView', () => {
  it('estimasi awal dan jumlah tanpa harga awal diambil dari nilai beku server, bukan dihitung ulang', () => {
    const v = buildActiveView(session(), [item('a', { price_snapshot: '1000', quantity_needed: '5' })])
    expect(v.frozen).toEqual({ total: '99999', unpricedCount: 7 })
  })

  it('total berjalan dihitung dari barang, terpisah dari nilai beku (FR-050)', () => {
    const v = buildActiveView(session(), [
      item('a', { status: 'in_cart', price_snapshot: '1000', quantity_actual: '2' }),
      item('b', { status: 'purchased', quantity_actual: '1' }),
    ])
    expect(v.running).toEqual({ total: '2000', pricedCount: 1, unpricedCount: 1, incomplete: true })
    expect(v.frozen.unpricedCount).toBe(7)
  })

  it('mengelompokkan per status berurutan, membuang kelompok kosong dan barang yang dihapus', () => {
    const v = buildActiveView(session(), [
      item('c', { status: 'purchased', quantity_actual: '1' }),
      item('a', { status: 'to_buy' }),
      item('b', { status: 'in_cart', quantity_actual: '1' }),
      item('d', { status: 'to_buy', source_item_id: null, deleted_at: '2026-11-20T08:00:00Z' }),
    ])
    expect(v.groups.map((g) => g.status)).toEqual(['to_buy', 'in_cart', 'purchased'])
    expect(v.itemCount).toBe(3)
    expect(v.groups.flatMap((g) => g.items.map((i) => i.id))).toEqual(['a', 'b', 'c'])
    expect(buildActiveView(session(), [item('x')]).groups.map((g) => g.status)).toEqual(['to_buy'])
    expect(buildActiveView(session(), []).groups).toEqual([])
  })

  it('harga efektif: aktual menang, 0 sah, tanpa harga tetap null', () => {
    const v = buildActiveView(session(), [
      item('a', { status: 'in_cart', price_snapshot: '10000', price_actual: '11000', quantity_actual: '2' }),
      item('b', { status: 'in_cart', price_snapshot: '10000', quantity_actual: '2' }),
      item('c', { status: 'in_cart', price_snapshot: '9000', price_actual: '0', quantity_actual: '3' }),
      item('d', { status: 'in_cart', quantity_actual: '1' }),
    ])
    const by = Object.fromEntries(v.groups[0]!.items.map((i) => [i.id, i]))
    expect(by.a).toMatchObject({ price: '11000', priceIsActual: true, subtotal: '22000' })
    expect(by.b).toMatchObject({ price: '10000', priceIsActual: false, subtotal: '20000' })
    expect(by.c).toMatchObject({ price: '0', priceIsActual: true, subtotal: '0' })
    expect(by.d).toMatchObject({ price: null, subtotal: null })
  })

  it('barang to_buy tidak punya subtotal walau berharga, dan penanda langsung terbaca', () => {
    const v = buildActiveView(session(), [item('a', { price_snapshot: '5000' }), item('b', { source_item_id: null })])
    const by = Object.fromEntries(v.groups[0]!.items.map((i) => [i.id, i]))
    expect(by.a).toMatchObject({ price: '5000', subtotal: null, direct: false })
    expect(by.b?.direct).toBe(true)
  })
})

describe('buildCompletedView', () => {
  it('hanya sesi completed yang punya ringkasan (FR-040)', () => {
    expect(buildCompletedView(null, [])).toBeNull()
    expect(buildCompletedView(session({ status: 'active' }), [])).toBeNull()
    expect(buildCompletedView(session({ status: 'cancelled', ended_at: '2026-11-20T09:00:00Z' }), [])).toBeNull()
  })

  it('total aktual dan jumlah tanpa harga dibeli diambil dari nilai beku server', () => {
    const s = session({
      status: 'completed', ended_at: '2026-11-20T09:00:00Z', total_actual: '12000', unpriced_items_purchased: 1,
    })
    const v = buildCompletedView(s, [
      item('p1', { status: 'purchased', price_actual: '2000', quantity_actual: '1', quantity_needed: '3' }),
      item('p2', { status: 'purchased', quantity_actual: '1' }),
      item('x', { status: 'to_buy', quantity_needed: '2' }),
      item('r', { status: 'to_buy', source_item_id: null, deleted_at: '2026-11-20T08:00:00Z' }),
    ])
    expect(v).toEqual({
      endedAt: '2026-11-20T09:00:00Z',
      totalActual: '12000',
      unpricedPurchased: 1,
      estimate: { total: '99999', unpricedCount: 7 },
      purchasedCount: 2,
      returnCount: 2,
    })
  })
})
