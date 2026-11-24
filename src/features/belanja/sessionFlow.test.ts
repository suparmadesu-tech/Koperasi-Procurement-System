import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import {
  createSessionFlow,
  endGuard,
  noGuard,
  startGuard,
  type FlowConfig,
  type FlowPhase,
  type GuardOutcome,
  type SettledOutcome,
} from './sessionFlow'

const OK_GUARD: GuardOutcome = { kind: 'ok', note: 'catatan', warning: null }
const ok = (opId: string, data: Record<string, unknown> = {}): ListOpResult => ({
  ok: true,
  opId,
  data,
  replayed: false,
})
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})

function setup(over: Partial<FlowConfig> = {}, guards: GuardOutcome[] = []) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  const settled: SettledOutcome[] = []
  let guardCalls = 0
  let discards = 0
  let n = 0
  const cfg: FlowConfig = {
    opType: 'kps_start_session',
    payload: () => ({}),
    guard: async () => {
      guardCalls += 1
      return guards.shift() ?? OK_GUARD
    },
    recheckBeforeSend: true,
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    isOnline: () => true,
    newId: () => `op-${++n}`,
    onDiscard: () => {
      discards += 1
    },
    onSettled: (o) => {
      settled.push(o)
    },
    ...over,
  }
  return {
    flow: createSessionFlow(cfg),
    calls,
    results,
    settled,
    guardCalls: () => guardCalls,
    discards: () => discards,
  }
}

describe('mulai sesi: penjaga antrean (FR-045)', () => {
  it('diblokir penjaga: pesan tampil dan RPC tidak pernah dipanggil', async () => {
    const t = setup({}, [{ kind: 'blocked', message: 'Ada 2 perubahan belum tersimpan di server.' }])
    await t.flow.begin()
    const s = t.flow.getState()
    expect(s.phase).toBe('failed')
    expect(s.failure).toMatchObject({ kind: 'guard', message: 'Ada 2 perubahan belum tersimpan di server.' })
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
  })

  it('diizinkan: dialog konfirmasi membawa catatan pengingat, belum ada RPC', async () => {
    const t = setup()
    await t.flow.begin()
    expect(t.flow.getState()).toMatchObject({ phase: 'confirm', note: 'catatan', warning: null })
    expect(t.calls).toHaveLength(0)
  })

  it('antrean diperiksa sekali lagi tepat sebelum kirim', async () => {
    const t = setup()
    await t.flow.begin()
    t.results.push(ok('op-1', { session_id: 's1' }))
    await t.flow.confirm()
    expect(t.guardCalls()).toBe(2)
    expect(t.calls).toHaveLength(1)
    expect(t.flow.getState()).toMatchObject({ phase: 'done', result: { session_id: 's1' } })
  })

  it('antrean berubah di antara dialog dan kirim: diblokir tanpa RPC', async () => {
    const t = setup({}, [OK_GUARD, { kind: 'blocked', message: 'Antrean tidak kosong.' }])
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
    expect(t.flow.getState().failure).toMatchObject({ kind: 'guard', retryable: false })
  })

  it('offline: gagal tanpa memeriksa antrean dan tanpa RPC', async () => {
    const t = setup({ isOnline: () => false })
    await t.flow.begin()
    expect(t.flow.getState().failure).toMatchObject({ kind: 'offline', code: 'OFFLINE' })
    expect(t.guardCalls()).toBe(0)
    expect(t.calls).toHaveLength(0)
  })
})

describe('kunci double-submit', () => {
  it('klik ganda pada konfirmasi hanya mengirim satu RPC', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: async (_type, _payload, o) => {
        sent.push(o.opId)
        return gate
      },
    })
    await t.flow.begin()
    const p1 = t.flow.confirm()
    const p2 = t.flow.confirm()
    const p3 = t.flow.confirm()
    expect(t.flow.getState().phase).toBe('sending')
    release(ok('op-1'))
    await Promise.all([p1, p2, p3])
    expect(sent).toEqual(['op-1'])
    expect(t.flow.getState().phase).toBe('done')
  })

  it('klik ganda pada tombol utama hanya memeriksa penjaga sekali', async () => {
    const t = setup()
    await Promise.all([t.flow.begin(), t.flow.begin()])
    expect(t.guardCalls()).toBe(1)
    expect(t.flow.getState().phase).toBe('confirm')
  })

  it('begin diabaikan selama dialog terbuka dan konfirmasi di luar dialog tidak mengirim apa pun', async () => {
    const t = setup()
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
    await t.flow.begin()
    await t.flow.begin()
    expect(t.guardCalls()).toBe(1)
  })
})

describe('kirim ulang dengan op_id yang sama (SYNC-004)', () => {
  it('gagal jaringan menyimpan percobaan; retry memakai op_id dan payload yang sama', async () => {
    const t = setup({ opType: 'kps_end_session', payload: () => ({ session_id: 's1' }), recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1', { returned_items: 2 }))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.flow.hasPending()).toBe(true)

    await t.flow.retry()
    expect(t.flow.getState().phase).toBe('done')
    expect(t.flow.hasPending()).toBe(false)
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.calls[0]).toEqual({ type: 'kps_end_session', payload: { session_id: 's1' }, opId: 'op-1' })
  })

  it('selama percobaan menunggu, begin tidak membuat op_id baru', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('failed')
    expect(t.guardCalls()).toBe(1)
  })

  it('retry yang gagal lagi tetap memakai op_id yang sama', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.retry()
    expect(t.flow.hasPending()).toBe(true)
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('retry diblokir penjaga: percobaan tetap tersimpan dan RPC tidak dikirim lagi', async () => {
    const t = setup({}, [OK_GUARD, OK_GUARD, { kind: 'blocked', message: 'Antrean tidak kosong.' }])
    t.results.push(bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.retry()
    expect(t.calls).toHaveLength(1)
    expect(t.flow.getState().failure).toMatchObject({ kind: 'guard', retryable: true })
    expect(t.flow.hasPending()).toBe(true)
  })

  it('retry tanpa percobaan menunggu tidak melakukan apa pun', async () => {
    const t = setup()
    await t.flow.retry()
    expect(t.calls).toHaveLength(0)
    expect(t.flow.getState().phase).toBe('idle')
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan op_id berikutnya baru', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-2'))
    await t.flow.begin()
    await t.flow.confirm()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.flow.hasPending()).toBe(false)
    expect(t.discards()).toBe(1)

    await t.flow.begin()
    await t.flow.confirm()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })
})

describe('ditolak server berbeda dari gagal jaringan (SYNC-020)', () => {
  it('penolakan: tidak dapat diulang, tercatat sebagai rejected, dan tombol utama boleh dipakai lagi', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'KPS_SESSION_ALREADY_ACTIVE', false), ok('op-2'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().failure).toMatchObject({
      kind: 'rejected',
      code: 'KPS_SESSION_ALREADY_ACTIVE',
      retryable: false,
    })
    expect(t.flow.hasPending()).toBe(false)
    await t.flow.retry()
    expect(t.calls).toHaveLength(1)

    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('confirm')
    expect(t.flow.getState().failure).toBeNull()
    await t.flow.confirm()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('OFFLINE dan NO_CLIENT dari pengirim dibaca sebagai offline, bukan penolakan server', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'OFFLINE', false))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().failure?.kind).toBe('offline')
  })

  it('hasil akhir dilaporkan sekali per percobaan lewat onSettled', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'KPS_SESSION_NOT_ACTIVE', false))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.settled).toHaveLength(1)
    expect(t.settled[0]).toMatchObject({ ok: false, failure: { kind: 'rejected', code: 'KPS_SESSION_NOT_ACTIVE' } })

    t.results.push(ok('op-2', { item_count: 3 }))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.settled[1]).toEqual({ ok: true, data: { item_count: 3 } })
  })

  it('galat tak terduga tidak membuat alur macet di fase sending', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(new Error('meledak'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('failed')
    expect(t.flow.getState().failure).toMatchObject({ kind: 'unexpected', retryable: false })
    await t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
  })
})

describe('akhiri sesi: konfirmasi kedua (FR-028, SYNC-012)', () => {
  const warn: GuardOutcome = { kind: 'ok', note: '', warning: 'Ada 2 perubahan belum tersimpan di server.' }

  it('dengan peringatan, konfirmasi pertama tidak mengirim; baru konfirmasi kedua mengirim', async () => {
    const t = setup({ opType: 'kps_end_session', payload: () => ({ session_id: 's1' }), recheckBeforeSend: false }, [warn])
    t.results.push(ok('op-1'))
    await t.flow.begin()
    expect(t.flow.getState()).toMatchObject({ phase: 'confirm', warning: 'Ada 2 perubahan belum tersimpan di server.' })
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('confirm_warning')
    expect(t.calls).toHaveLength(0)
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('done')
    expect(t.calls).toHaveLength(1)
    expect(t.guardCalls()).toBe(1)
  })

  it('membatalkan di dialog kedua tidak mengirim apa pun', async () => {
    const t = setup({ recheckBeforeSend: false }, [warn])
    await t.flow.begin()
    await t.flow.confirm()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
  })

  it('tanpa peringatan, satu konfirmasi cukup', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(ok('op-1'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('done')
  })
})

describe('batalkan sesi tanpa penjaga', () => {
  it('konfirmasi langsung mengirim kps_cancel_session', async () => {
    const t = setup({
      opType: 'kps_cancel_session',
      payload: () => ({ session_id: 's1' }),
      guard: noGuard,
      recheckBeforeSend: false,
    })
    t.results.push(ok('op-1', { returned_items: 4 }))
    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('confirm')
    await t.flow.confirm()
    expect(t.calls).toEqual([{ type: 'kps_cancel_session', payload: { session_id: 's1' }, opId: 'op-1' }])
  })

  it('menutup dialog tidak mengirim apa pun', async () => {
    const t = setup({ guard: noGuard, recheckBeforeSend: false })
    await t.flow.begin()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
  })
})

describe('perubahan fase terlihat oleh pelanggan', () => {
  it('urutan fase mulai sesi yang berhasil', async () => {
    const t = setup()
    const phases: FlowPhase[] = []
    t.flow.subscribe(() => phases.push(t.flow.getState().phase))
    t.results.push(ok('op-1'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(phases).toEqual(['checking', 'confirm', 'sending', 'done'])
  })
})

describe('adaptor penjaga', () => {
  it('startGuard: diizinkan membawa pengingat, ditolak membawa alasan', async () => {
    expect(await startGuard(async () => ({ allowed: true, message: 'ingat' }))()).toEqual({
      kind: 'ok',
      note: 'ingat',
      warning: null,
    })
    expect(await startGuard(async () => ({ allowed: false, message: 'blokir' }))()).toEqual({
      kind: 'blocked',
      message: 'blokir',
    })
  })

  it('endGuard: tidak pernah memblokir, hanya menambah peringatan bila perlu konfirmasi', async () => {
    expect(await endGuard(async () => ({ needsConfirm: false, message: 'ingat' }))()).toEqual({
      kind: 'ok',
      note: 'ingat',
      warning: null,
    })
    expect(await endGuard(async () => ({ needsConfirm: true, message: 'awas' }))()).toEqual({
      kind: 'ok',
      note: '',
      warning: 'awas',
    })
  })
})
