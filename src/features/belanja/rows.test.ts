import { describe, expect, it } from 'vitest'
import { toSessionItemRow, toSessionRow } from './rows'
import type { ServerSession, ServerSessionItem } from './types'

const session: ServerSession = {
  id: 's1', workspace_id: 'w', status: 'active', started_by: 'u', started_at: '', ended_by: null, ended_at: null,
  total_estimate: 15000, unpriced_items_at_start: 2, total_actual: null, unpriced_items_purchased: null,
  created_at: '', updated_at: '',
}

const item: ServerSessionItem = {
  id: 'i1', session_id: 's1', workspace_id: 'w', source_item_id: null, product_id: null,
  product_name_snapshot: 'A', photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null,
  allow_fraction_snapshot: true, note_snapshot: null, price_snapshot: 3333, price_actual: null,
  quantity_needed: 0.5, quantity_actual: '2.000', status: 'in_cart', deleted_at: null, created_at: '', updated_at: '',
}

describe('rows sesi', () => {
  it('mengubah angka server menjadi string desimal dan menjaga null', () => {
    const s = toSessionRow(session)
    expect(s.total_estimate).toBe('15000')
    expect(s.total_actual).toBeNull()
    expect(s.unpriced_items_at_start).toBe(2)
  })

  it('barang sesi: harga dan kuantitas menjadi string, null tetap null', () => {
    const r = toSessionItemRow(item)
    expect(r.price_snapshot).toBe('3333')
    expect(r.price_actual).toBeNull()
    expect(r.quantity_needed).toBe('0.5')
    expect(r.quantity_actual).toBe('2')
  })
})
