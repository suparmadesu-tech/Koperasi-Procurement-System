import { describe, expect, it } from 'vitest'
import { selectSessionState } from './sessionSelectors'
import type { SessionItemRow, SessionRow } from './types'

const session = (id: string, status: SessionRow['status'], ended_at: string | null): SessionRow => ({
  id, workspace_id: 'w', status, started_by: null, started_at: '2026-11-01T00:00:00Z', ended_by: null, ended_at,
  total_estimate: '0', unpriced_items_at_start: 0, total_actual: null, unpriced_items_purchased: null,
  created_at: '2026-11-01T00:00:00Z', updated_at: '',
})

const item = (id: string, session_id: string, name: string, deleted_at: string | null = null): SessionItemRow => ({
  id, session_id, workspace_id: 'w', source_item_id: null, product_id: null, product_name_snapshot: name,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: null, price_actual: null, quantity_needed: '1', quantity_actual: null,
  status: 'to_buy', deleted_at, created_at: '', updated_at: '',
})

describe('selectSessionState', () => {
  it('memisahkan sesi aktif dari sesi berakhir terbaru dan membuang barang yang dihapus', () => {
    const s = selectSessionState({
      sessions: [
        session('a', 'active', null),
        session('c1', 'completed', '2026-11-10T00:00:00Z'),
        session('c2', 'cancelled', '2026-11-12T00:00:00Z'),
      ],
      items: [item('i2', 'a', 'Gula'), item('i1', 'a', 'Beras'), item('i3', 'a', 'Hapus', 'x'), item('i4', 'c2', 'Teh')],
    })
    expect(s.active?.id).toBe('a')
    expect(s.activeItems.map((i) => i.product_name_snapshot)).toEqual(['Beras', 'Gula'])
    expect(s.lastEnded?.id).toBe('c2')
    expect(s.lastEndedItems.map((i) => i.id)).toEqual(['i4'])
  })

  it('tanpa sesi aktif atau sesi apa pun', () => {
    const none = selectSessionState({ sessions: [], items: [] })
    expect(none).toEqual({ active: null, activeItems: [], lastEnded: null, lastEndedItems: [] })
    const onlyEnded = selectSessionState({ sessions: [session('c', 'completed', '2026-11-10T00:00:00Z')], items: [] })
    expect(onlyEnded.active).toBeNull()
    expect(onlyEnded.lastEnded?.id).toBe('c')
  })
})
