import { describe, expect, it } from 'vitest'
import { buildActiveView } from './sessionView'
import type { SessionItemRow, SessionRow } from './types'

const session = (): SessionRow => ({
  id: 's', workspace_id: 'w', status: 'active', started_by: null, started_at: '2026-11-20T07:00:00Z',
  ended_by: null, ended_at: null, total_estimate: '5000', unpriced_items_at_start: 0, total_actual: null,
  unpriced_items_purchased: null, created_at: '', updated_at: '',
})

const item = (id: string, extra: Partial<SessionItemRow> = {}): SessionItemRow => ({
  id, session_id: 's', workspace_id: 'w', source_item_id: 'src', product_id: null, product_name_snapshot: id,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: '1000', price_actual: null, quantity_needed: '2', quantity_actual: null,
  status: 'to_buy', deleted_at: null, created_at: '', updated_at: '', ...extra,
})

describe('allowFraction dari snapshot', () => {
  it('mengikuti allow_fraction_snapshot per barang', () => {
    const v = buildActiveView(session(), [
      item('a', { allow_fraction_snapshot: true }),
      item('b', { allow_fraction_snapshot: false }),
    ])
    const by = Object.fromEntries(v.groups.flatMap((g) => g.items).map((i) => [i.id, i.allowFraction]))
    expect(by).toEqual({ a: true, b: false })
  })
})

describe('total berjalan mengikuti nilai server setelah penyegaran', () => {
  it('data baru dari server menghasilkan total berjalan baru; estimasi awal tetap nilai beku', () => {
    const before = buildActiveView(session(), [item('a', { status: 'to_buy' })])
    expect(before.running).toMatchObject({ total: '0', pricedCount: 0, unpricedCount: 0 })

    // Setelah server mengisi jumlah aktual awal = kebutuhan saat keluar dari to_buy (FR-032) dan layar disegarkan.
    const afterStatus = buildActiveView(session(), [item('a', { status: 'in_cart', quantity_actual: '2' })])
    expect(afterStatus.running).toMatchObject({ total: '2000', pricedCount: 1 })

    // Harga aktual dikonfirmasi server.
    const afterPrice = buildActiveView(session(), [
      item('a', { status: 'in_cart', quantity_actual: '2', price_actual: '1500' }),
    ])
    expect(afterPrice.running.total).toBe('3000')

    // Kembali ke to_buy: server mengosongkan jumlah aktual dan menyentuh price_actual tidak.
    const back = buildActiveView(session(), [item('a', { status: 'to_buy', quantity_actual: null, price_actual: '1500' })])
    expect(back.running).toMatchObject({ total: '0', pricedCount: 0 })
    expect(back.groups[0]?.items[0]).toMatchObject({ price: '1500', priceIsActual: true, subtotal: null })

    expect(before.frozen).toEqual(afterPrice.frozen)
    expect(before.frozen).toEqual({ total: '5000', unpricedCount: 0 })
  })

  it('barang tanpa harga tidak pernah menjadi Rp 0 dan menandai belum lengkap', () => {
    const v = buildActiveView(session(), [item('a', { status: 'in_cart', quantity_actual: '2', price_snapshot: null })])
    expect(v.running).toMatchObject({ total: '0', pricedCount: 0, unpricedCount: 1, incomplete: true })
    expect(v.groups[0]?.items[0]).toMatchObject({ price: null, subtotal: null })
  })

  it('total aktual berjalan tidak diekspos; hanya nilai beku saat selesai (FR-050)', () => {
    const v = buildActiveView(session(), [item('a', { status: 'purchased', quantity_actual: '2' })])
    expect(Object.keys(v).sort()).toEqual(['frozen', 'groups', 'itemCount', 'running', 'startedAt'])
  })
})
