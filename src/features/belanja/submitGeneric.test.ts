import { describe, expect, it } from 'vitest'
import { createAttemptRunner } from '../daftar/attemptRunner'
import { createSubmitter, type RpcReply, type SubmitDeps } from '../daftar/submitCore'
import { sessionMessageForCode } from './sessionErrors'
import { toRpcCall, type RpcCall } from './sessionRpc'

const accepted = (data: Record<string, unknown> = {}): RpcReply => ({
  data: { op_id: 'x', status: 'diterima', code: null, message: null, data, replayed: false },
  error: null,
  status: 200,
})
const rejected = (code: string): RpcReply => ({
  data: { op_id: 'x', status: 'ditolak', code, message: 'dari server', data: {}, replayed: false },
  error: null,
  status: 200,
})

function setup(replies: Array<RpcReply | Error>, over: Partial<SubmitDeps> = {}) {
  const calls: RpcCall[] = []
  const deps: SubmitDeps = {
    rpc: async (args) => {
      calls.push(toRpcCall(args))
      const next = replies.shift()
      if (!next) throw new Error('tidak ada balasan terjadwal')
      if (next instanceof Error) throw next
      return next
    },
    refreshSession: async () => true,
    isOnline: () => true,
    newId: () => 'op-1',
    messageFor: sessionMessageForCode,
    offlineMessage: 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.',
    ...over,
  }
  return { deps, calls }
}

describe('createSubmitter dengan operasi sesi', () => {
  it('mulai sesi dipanggil sebagai RPC sendiri dengan op_id dari submitter', async () => {
    const { deps, calls } = setup([accepted({ session_id: 's1', item_count: 3 })])
    const r = await createSubmitter(deps)('w1', 'kps_start_session', {})
    expect(r).toMatchObject({ ok: true, opId: 'op-1', data: { session_id: 's1', item_count: 3 } })
    expect(calls).toEqual([{ fn: 'kps_start_session', args: { p_workspace_id: 'w1', p_op_id: 'op-1' } }])
  })

  it('penolakan memakai pesan sesi', async () => {
    const a = await createSubmitter(setup([rejected('KPS_SESSION_NOT_ACTIVE')]).deps)('w1', 'session_set_status', {})
    expect(!a.ok && a.message).toContain('selesai atau dibatalkan')
    const b = await createSubmitter(setup([rejected('KPS_ITEM_DELETED')]).deps)('w1', 'session_set_status', {})
    expect(!b.ok && b.message).toContain('dihapus dari sesi')
    expect(!b.ok && b.retryable).toBe(false)
  })

  it('offline memakai pesan khusus dan tidak mengirim apa pun', async () => {
    const { deps, calls } = setup([], { isOnline: () => false })
    const r = await createSubmitter(deps)('w1', 'kps_start_session', {})
    expect(r).toMatchObject({ ok: false, code: 'OFFLINE' })
    expect(!r.ok && r.message).toContain('sesi belanja')
    expect(calls).toHaveLength(0)
  })
})

describe('createAttemptRunner dengan tipe operasi sesi', () => {
  it('mengakhiri sesi dikirim ulang dengan op_id dan session_id yang sama (SYNC-004)', async () => {
    const { deps, calls } = setup([new TypeError('Failed to fetch'), accepted({ session_id: 's1', returned_items: 2 })])
    const submit = createSubmitter(deps)
    const runner = createAttemptRunner((type, payload, options) => submit('w1', type, payload, options), () => 'op-r')

    const first = await runner.run('kps_end_session', { session_id: 's1' })
    expect(first).toMatchObject({ ok: false, code: 'NETWORK', retryable: true, opId: 'op-r' })
    expect(runner.hasPending()).toBe(true)

    const second = await runner.retry()
    expect(second).toMatchObject({ ok: true, opId: 'op-r' })
    expect(runner.hasPending()).toBe(false)
    expect(calls).toHaveLength(2)
    expect(calls[1]).toEqual(calls[0])
    expect(calls[0]).toEqual({
      fn: 'kps_end_session',
      args: { p_workspace_id: 'w1', p_op_id: 'op-r', p_session_id: 's1' },
    })
  })

  it('penolakan tidak menyisakan percobaan untuk dikirim ulang', async () => {
    const { deps } = setup([rejected('KPS_SESSION_ALREADY_ACTIVE')])
    const submit = createSubmitter(deps)
    const runner = createAttemptRunner((type, payload, options) => submit('w1', type, payload, options), () => 'op-r')
    const r = await runner.run('kps_start_session', {})
    expect(r).toMatchObject({ ok: false, code: 'KPS_SESSION_ALREADY_ACTIVE', retryable: false })
    expect(runner.hasPending()).toBe(false)
  })
})
