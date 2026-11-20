import { describe, expect, it } from 'vitest'
import { createSubmitter, type RpcReply, type SubmitDeps } from './submitCore'

type Scripted = RpcReply | Error

function makeDeps(replies: Scripted[], over: Partial<SubmitDeps> = {}) {
  const calls: Array<Parameters<SubmitDeps['rpc']>[0]> = []
  let refreshes = 0
  const deps: SubmitDeps = {
    rpc: async (args) => {
      calls.push(args)
      const next = replies.shift()
      if (!next) throw new Error('tidak ada balasan terjadwal')
      if (next instanceof Error) throw next
      return next
    },
    refreshSession: async () => {
      refreshes += 1
      return true
    },
    isOnline: () => true,
    newId: () => 'op-fixed',
    ...over,
  }
  return { deps, calls, refreshes: () => refreshes }
}

const accepted = (data: Record<string, unknown> = {}, replayed = false): RpcReply => ({
  data: { op_id: 'op-fixed', status: 'diterima', code: null, message: null, data, replayed },
  error: null,
  status: 200,
})
const rejected = (code: string): RpcReply => ({
  data: { op_id: 'op-fixed', status: 'ditolak', code, message: 'pesan server', data: {}, replayed: false },
  error: null,
  status: 200,
})
const failed = (error: unknown, status: number): RpcReply => ({ data: null, error, status })

const run = (deps: SubmitDeps, options = {}) =>
  createSubmitter(deps)('w1', 'list_set_quantity', { item_id: 'i1', quantity: 2 }, options)

describe('submitListOp (inti)', () => {
  it('sukses mengirim p_workspace_id, p_op_id, p_op_type, p_payload dan mengembalikan data', async () => {
    const { deps, calls } = makeDeps([accepted({ item_id: 'i1' })])
    const r = await run(deps)
    expect(r).toEqual({ ok: true, opId: 'op-fixed', data: { item_id: 'i1' }, replayed: false })
    expect(calls).toEqual([
      { p_workspace_id: 'w1', p_op_id: 'op-fixed', p_op_type: 'list_set_quantity', p_payload: { item_id: 'i1', quantity: 2 } },
    ])
  })

  it('meneruskan replayed dari server (SYNC-004)', async () => {
    const { deps } = makeDeps([accepted({}, true)])
    const r = await run(deps)
    expect(r.ok && r.replayed).toBe(true)
  })

  it('penolakan bisnis menjadi galat tidak dapat diulang dengan pesan Indonesia', async () => {
    const { deps, calls } = makeDeps([rejected('KPS_ITEM_MOVED')])
    const r = await run(deps)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.code).toBe('KPS_ITEM_MOVED')
      expect(r.retryable).toBe(false)
      expect(r.message).toContain('sesi belanja')
    }
    expect(calls).toHaveLength(1)
  })

  it('kode penolakan yang tidak dikenal memakai pesan server', async () => {
    const { deps } = makeDeps([rejected('KPS_BARU')])
    const r = await run(deps)
    expect(!r.ok && r.message).toBe('pesan server')
  })

  it('galat jaringan dapat diulang dan opId dari pemanggil dipakai ulang', async () => {
    const { deps, calls } = makeDeps([new TypeError('Failed to fetch')])
    const r = await run(deps, { opId: 'op-given' })
    expect(r).toMatchObject({ ok: false, opId: 'op-given', code: 'NETWORK', retryable: true })
    expect(calls[0]?.p_op_id).toBe('op-given')
  })

  it('KPS_INTERNAL dan jawaban tak dikenal dapat diulang', async () => {
    const a = await run(makeDeps([failed({ code: 'KPS_INTERNAL', message: 'KPS_INTERNAL: x' }, 400)]).deps)
    expect(a).toMatchObject({ ok: false, code: 'SERVER_ERROR', retryable: true })
    const b = await run(makeDeps([{ data: { aneh: true }, error: null, status: 200 }]).deps)
    expect(b).toMatchObject({ ok: false, code: 'SERVER_ERROR', retryable: true })
  })

  it('KPS_FORBIDDEN: sesi disegarkan sekali lalu dikirim ulang dengan op_id sama', async () => {
    const { deps, calls, refreshes } = makeDeps([failed({ code: 'KPS_FORBIDDEN', message: 'x' }, 403), accepted()])
    const r = await run(deps)
    expect(r.ok).toBe(true)
    expect(refreshes()).toBe(1)
    expect(calls).toHaveLength(2)
    expect(calls[1]?.p_op_id).toBe(calls[0]?.p_op_id)
  })

  it('KPS_FORBIDDEN yang berulang setelah refresh berakhir gagal', async () => {
    const e = failed({ code: 'KPS_FORBIDDEN', message: 'x' }, 403)
    const { deps, calls, refreshes } = makeDeps([e, e])
    const r = await run(deps)
    expect(r).toMatchObject({ ok: false, code: 'KPS_FORBIDDEN', retryable: false })
    expect(refreshes()).toBe(1)
    expect(calls).toHaveLength(2)
  })

  it('HTTP 401: token disegarkan lalu dikirim ulang', async () => {
    const { deps, refreshes } = makeDeps([failed({ code: 'PGRST301', message: 'JWT expired' }, 401), accepted()])
    expect((await run(deps)).ok).toBe(true)
    expect(refreshes()).toBe(1)
  })

  it('HTTP 401 berulang atau refresh gagal meminta login ulang', async () => {
    const e = failed({ code: 'PGRST301', message: 'JWT expired' }, 401)
    expect(await run(makeDeps([e, e]).deps)).toMatchObject({ ok: false, code: 'SESSION_EXPIRED' })
    const { deps, calls } = makeDeps([e], { refreshSession: async () => false })
    expect(await run(deps)).toMatchObject({ ok: false, code: 'SESSION_EXPIRED' })
    expect(calls).toHaveLength(1)
  })

  it('KPS_INVALID_INPUT langsung gagal tanpa ulang', async () => {
    const { deps, calls } = makeDeps([failed({ code: 'KPS_INVALID_INPUT', message: 'x' }, 400)])
    expect(await run(deps)).toMatchObject({ ok: false, code: 'KPS_INVALID_INPUT', retryable: false })
    expect(calls).toHaveLength(1)
  })

  it('offline tidak mengirim apa pun', async () => {
    const { deps, calls } = makeDeps([], { isOnline: () => false })
    expect(await run(deps)).toMatchObject({ ok: false, code: 'OFFLINE', retryable: false })
    expect(calls).toHaveLength(0)
  })
})
