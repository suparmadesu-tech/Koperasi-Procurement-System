import type { SupabaseClient } from '@supabase/supabase-js'
import { requestListRefresh } from '../daftar/listSync'
import { createSubmitter, type SubmitOptions } from '../daftar/submitCore'
import type { ListOpResult } from '../daftar/types'
import { isOnline } from '../katalog/catalogStore'
import { refreshSupabaseSession, sbClient } from './rpcDeps'
import { sessionMessageForCode } from './sessionErrors'
import { toRpcCall, type SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'

export type SessionOpResult = ListOpResult

const core = createSubmitter({
  rpc: async (args) => {
    const call = toRpcCall(args)
    const res = await (sbClient as SupabaseClient).rpc(call.fn, call.args)
    return { data: res.data as unknown, error: res.error as unknown, status: res.status }
  },
  refreshSession: refreshSupabaseSession,
  isOnline,
  newId: () => crypto.randomUUID(),
  messageFor: sessionMessageForCode,
  offlineMessage: 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.',
})

const RETURNS_TO_LIST: readonly SessionOpType[] = ['kps_start_session', 'kps_end_session', 'kps_cancel_session']
const NO_REFRESH_CODES = ['OFFLINE', 'NO_CLIENT', 'SESSION_EXPIRED']

// Titik tunggal penulisan sesi. Antarmukanya sama dengan submitListOp; Tahap 6 mengganti isinya
// menjadi antrean offline untuk operasi yang boleh offline. Gunakan opId yang sama untuk kirim ulang.
export function submitSessionOp(
  workspaceId: string,
  opType: SessionOpType,
  payload: Record<string, unknown>,
  options: SubmitOptions = {},
): Promise<SessionOpResult> {
  if (!sbClient) {
    return Promise.resolve({
      ok: false,
      opId: options.opId ?? crypto.randomUUID(),
      code: 'NO_CLIENT',
      message: 'Supabase belum dikonfigurasi.',
      retryable: false,
    })
  }
  return core(workspaceId, opType, payload, options).then((r) => {
    if (r.ok) {
      requestSessionRefresh()
      // Mulai, akhiri, dan batalkan memindahkan barang antara daftar dan sesi.
      if (RETURNS_TO_LIST.includes(opType)) requestListRefresh()
    } else if (!r.retryable && !NO_REFRESH_CODES.includes(r.code)) {
      // Ditolak server: ambil keadaan terbaru supaya layar sama dengan server.
      requestSessionRefresh()
    }
    return r
  })
}
