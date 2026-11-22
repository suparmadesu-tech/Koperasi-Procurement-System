import { classifyOutcome, normalizeSendError, type SendResult } from '../../lib/sync-errors'
import { messageForCode, messageForSendError } from './errors'
import type { ListOpResult } from './types'

export interface RpcReply {
  data: unknown
  error: unknown
  status?: number
}

export interface SubmitDeps {
  rpc: (args: {
    p_workspace_id: string
    p_op_id: string
    p_op_type: string
    p_payload: Record<string, unknown>
  }) => Promise<RpcReply>
  refreshSession: () => Promise<boolean>
  isOnline: () => boolean
  newId: () => string
  // Opsional: pesan khusus konteks (misalnya sesi belanja).
  messageFor?: (code: string | null | undefined, serverMessage?: string) => string
  offlineMessage?: string
}

export interface SubmitOptions {
  // Kirim ulang dengan opId yang sama setelah retryable: server menjawab replay, tanpa duplikasi (SYNC-004).
  opId?: string
}

type Body = Record<string, unknown>

function bodyOf(reply: RpcReply | null): Body | null {
  const b = reply?.data
  return typeof b === 'object' && b !== null ? (b as Body) : null
}

function toSendResult(reply: RpcReply): SendResult {
  if (reply.error) return { kind: 'error', error: normalizeSendError(reply.error, reply.status) }
  const b = bodyOf(reply)
  if (b && typeof b.status === 'string') {
    return { kind: 'response', status: b.status, code: typeof b.code === 'string' ? b.code : null }
  }
  return { kind: 'response', status: 'unknown' }
}

export function createSubmitter(deps: SubmitDeps) {
  return async function submit(
    workspaceId: string,
    opType: string,
    payload: Record<string, unknown>,
    options: SubmitOptions = {},
  ): Promise<ListOpResult> {
    const opId = options.opId ?? deps.newId()
    const say = deps.messageFor ?? messageForCode
    const fail = (code: string, message: string, retryable: boolean): ListOpResult => ({
      ok: false,
      opId,
      code,
      message,
      retryable,
    })

    if (!deps.isOnline()) {
      return fail(
        'OFFLINE',
        deps.offlineMessage ?? 'Anda sedang offline. Menulis daftar memerlukan koneksi internet.',
        false,
      )
    }

    let refreshed = false
    for (;;) {
      let reply: RpcReply | null = null
      let result: SendResult
      try {
        reply = await deps.rpc({
          p_workspace_id: workspaceId,
          p_op_id: opId,
          p_op_type: opType,
          p_payload: payload,
        })
        result = toSendResult(reply)
      } catch (e) {
        result = { kind: 'error', error: normalizeSendError(e) }
      }

      const action = classifyOutcome(result, { sessionRefreshed: refreshed })
      switch (action.type) {
        case 'success': {
          const b = bodyOf(reply)
          const data = b && typeof b.data === 'object' && b.data !== null ? (b.data as Body) : {}
          return { ok: true, opId, data, replayed: b?.replayed === true }
        }
        case 'fail_rejected': {
          const msg = bodyOf(reply)?.message
          return fail(
            action.code ?? 'KPS_REJECTED',
            say(action.code, typeof msg === 'string' ? msg : undefined),
            false,
          )
        }
        case 'fail_invalid':
          return fail(action.code, say(action.code), false)
        case 'fail_forbidden':
          return fail('KPS_FORBIDDEN', say('KPS_FORBIDDEN'), false)
        case 'refresh_and_resend': {
          const ok = await deps.refreshSession()
          if (!ok) {
            return fail('SESSION_EXPIRED', 'Sesi login tidak dapat disegarkan. Keluar lalu masuk kembali.', false)
          }
          refreshed = true
          continue
        }
        case 'needs_login':
          return fail('SESSION_EXPIRED', 'Sesi login berakhir. Keluar lalu masuk kembali.', false)
        case 'retry': {
          if (result.kind === 'error') {
            return fail(result.error.network ? 'NETWORK' : 'SERVER_ERROR', messageForSendError(result.error), true)
          }
          return fail('SERVER_ERROR', 'Jawaban server tidak dikenali. Coba lagi.', true)
        }
      }
    }
  }
}
