import type { SubmitDeps } from '../daftar/submitCore'

// Memiliki RPC sendiri (KPS-DB-Bagian-3, bagian 4).
export type DirectOp =
  | 'kps_start_session'
  | 'kps_end_session'
  | 'kps_cancel_session'
  | 'kps_add_catalog_to_session'

// Lewat kps_apply_op (bagian 5).
export type ApplyOp =
  | 'session_add_manual'
  | 'session_set_status'
  | 'session_set_quantity_actual'
  | 'session_set_price_actual'
  | 'session_set_quantity_needed'
  | 'session_delete_item'
  | 'session_set_photo'

export type SessionOpType = DirectOp | ApplyOp
export type RpcArgs = Parameters<SubmitDeps['rpc']>[0]

export interface RpcCall {
  fn: string
  args: Record<string, unknown>
}

// p_op_type memilih fungsi; kunci payload klien dipetakan ke nama parameter RPC.
export function toRpcCall(a: RpcArgs): RpcCall {
  const base = { p_workspace_id: a.p_workspace_id, p_op_id: a.p_op_id }
  const p = a.p_payload
  switch (a.p_op_type) {
    case 'kps_start_session':
      return { fn: 'kps_start_session', args: base }
    case 'kps_end_session':
    case 'kps_cancel_session':
      return { fn: a.p_op_type, args: { ...base, p_session_id: p.session_id } }
    case 'kps_add_catalog_to_session': {
      const args: Record<string, unknown> = {
        ...base,
        p_session_id: p.session_id,
        p_product_id: p.product_id,
        p_quantity: p.quantity,
      }
      if (typeof p.note === 'string') args.p_note = p.note
      return { fn: 'kps_add_catalog_to_session', args }
    }
    default:
      return { fn: 'kps_apply_op', args: { ...a } }
  }
}
