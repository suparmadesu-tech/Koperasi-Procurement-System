import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { isOnline } from '../katalog/catalogStore'
import { requestListRefresh } from './listSync'
import { createSubmitter, type SubmitOptions } from './submitCore'
import type { ListOpResult, ListOpType } from './types'

const sb = supabase as unknown as SupabaseClient | null

const core = createSubmitter({
  rpc: async (args) => {
    const res = await (sb as SupabaseClient).rpc('kps_apply_op', args)
    return { data: res.data as unknown, error: res.error as unknown, status: res.status }
  },
  refreshSession: async () => {
    const { data, error } = await (sb as SupabaseClient).auth.refreshSession()
    return !error && data.session !== null
  },
  isOnline,
  newId: () => crypto.randomUUID(),
})

// Titik tunggal penulisan daftar. Tahap 6 mengganti isinya menjadi antrean offline; layar tidak berubah.
export function submitListOp(
  workspaceId: string,
  opType: ListOpType,
  payload: Record<string, unknown>,
  options: SubmitOptions = {},
): Promise<ListOpResult> {
  if (!sb) {
    return Promise.resolve({
      ok: false,
      opId: options.opId ?? crypto.randomUUID(),
      code: 'NO_CLIENT',
      message: 'Supabase belum dikonfigurasi.',
      retryable: false,
    })
  }
  return core(workspaceId, opType, payload, options).then((r) => {
    if (r.ok) requestListRefresh()
    return r
  })
}
