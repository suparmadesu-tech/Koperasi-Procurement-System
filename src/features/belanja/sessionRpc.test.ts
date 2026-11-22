import { describe, expect, it } from 'vitest'
import { toRpcCall } from './sessionRpc'

const base = { p_workspace_id: 'w1', p_op_id: 'o1' }

describe('toRpcCall', () => {
  it('mulai sesi hanya membawa workspace dan op_id', () => {
    expect(toRpcCall({ ...base, p_op_type: 'kps_start_session', p_payload: {} })).toEqual({
      fn: 'kps_start_session',
      args: base,
    })
  })

  it('akhiri dan batalkan membawa p_session_id', () => {
    for (const fn of ['kps_end_session', 'kps_cancel_session']) {
      expect(toRpcCall({ ...base, p_op_type: fn, p_payload: { session_id: 's1' } })).toEqual({
        fn,
        args: { ...base, p_session_id: 's1' },
      })
    }
  })

  it('tambah katalog ke sesi menyertakan p_note hanya bila ada', () => {
    const payload = { session_id: 's1', product_id: 'p1', quantity: 2 }
    expect(toRpcCall({ ...base, p_op_type: 'kps_add_catalog_to_session', p_payload: payload }).args).toEqual({
      ...base,
      p_session_id: 's1',
      p_product_id: 'p1',
      p_quantity: 2,
    })
    expect(
      toRpcCall({ ...base, p_op_type: 'kps_add_catalog_to_session', p_payload: { ...payload, note: 'merah' } }).args,
    ).toMatchObject({ p_note: 'merah' })
  })

  it('operasi lain diteruskan utuh ke kps_apply_op', () => {
    const a = { ...base, p_op_type: 'session_set_status', p_payload: { item_id: 'i1', status: 'in_cart' } }
    expect(toRpcCall(a)).toEqual({ fn: 'kps_apply_op', args: a })
  })
})
