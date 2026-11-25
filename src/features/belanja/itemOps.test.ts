import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import { createItemOps, type ItemOpsConfig } from './itemOps'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})

function setup(over: Partial<ItemOpsConfig> = {}) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  let discards = 0
  let n = 0
  const ops = createItemOps({
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    newId: () => `op-${++n}`,
    isOnline: () => true,
    onDiscard: () => {
      discards += 1
    },
    ...over,
  })
  return { ops, calls, results, discards: () => discards }
}

const P = { item_id: 'a', status: 'in_cart' }

describe('kunci per barang', () => {
  it('sukses: satu pengiriman, kembali idle, dan hasil dikonfirmasi tercatat', async () => {
    const t = setup()
    t.results.push(ok('op-1'))
    const out = await t.ops.run('a', 'session_set_status', P, 'Beras: status diubah.')
    expect(out).toEqual({ status: 'ok' })
    expect(t.ops.getItem('a')).toEqual({ phase: 'idle', failure: null })
    expect(t.ops.getLast()).toEqual({ seq: 1, text: 'Beras: status diubah.' })
    expect(t.calls).toEqual([{ type: 'session_set_status', payload: P, opId: 'op-1' }])
  })

  it('klik ganda pada barang yang sama hanya mengirim sekali', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: async (_t, _p, o) => {
        sent.push(o.opId)
        return gate
      },
    })
    const p1 = t.ops.run('a', 'session_set_status', P, 'x')
    const p2 = t.ops.run('a', 'session_set_status', P, 'x')
    const p3 = t.ops.run('a', 'session_set_quantity_actual', { item_id: 'a', quantity: 2 }, 'y')
    expect(t.ops.getItem('a').phase).toBe('sending')
    release(ok('op-1'))
    expect(await Promise.all([p1, p2, p3])).toEqual([{ status: 'ok' }, { status: 'ignored' }, { status: 'ignored' }])
    expect(sent).toEqual(['op-1'])
  })

  it('barang berbeda tidak saling mengunci dan memakai op_id berbeda', async () => {
    const gates: Array<(r: ListOpResult) => void> = []
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: (_t, _p, o) =>
        new Promise<ListOpResult>((res) => {
          sent.push(o.opId)
          gates.push(res)
        }),
    })
    const pa = t.ops.run('a', 'session_set_status', { item_id: 'a', status: 'purchased' }, 'a')
    const pb = t.ops.run('b', 'session_set_status', { item_id: 'b', status: 'purchased' }, 'b')
    expect(t.ops.getItem('a').phase).toBe('sending')
    expect(t.ops.getItem('b').phase).toBe('sending')
    expect(sent).toEqual(['op-1', 'op-2'])
    gates.forEach((g, i) => g(ok(`op-${i + 1}`)))
    await Promise.all([pa, pb])
    expect(t.ops.anyBusy()).toBe(false)
  })
})

describe('ditolak server berbeda dari gagal jaringan (SYNC-020)', () => {
  it('penolakan: tidak dapat diulang, dapat ditutup, dan niat baru memakai op_id baru', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'KPS_ITEM_DELETED', false), ok('op-2'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'rejected', code: 'KPS_ITEM_DELETED', retryable: false } })
    expect(t.ops.anyBusy()).toBe(false)
    expect(await t.ops.retry('a')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)

    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
    expect(t.ops.getItem('a').failure).toBeNull()
    expect(t.discards()).toBe(0)

    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('jaringan gagal: percobaan menunggu, niat baru diabaikan, retry memakai op_id dan payload lama', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.ops.anyBusy()).toBe(true)

    expect(await t.ops.run('a', 'session_set_status', { item_id: 'a', status: 'purchased' }, 'z')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)

    expect(await t.ops.retry('a')).toEqual({ status: 'ok' })
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.ops.anyBusy()).toBe(false)
    expect(t.ops.getLast()?.text).toBe('x')
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan op_id berikutnya baru', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-2'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
    expect(t.discards()).toBe(1)
    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('retry saat offline tidak memanggil pengirim dan percobaan tetap tersimpan', async () => {
    let online = true
    const t = setup({ isOnline: () => online })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    online = false
    expect(await t.ops.retry('a')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)
    expect(t.ops.getItem('a').phase).toBe('failed')
    online = true
    expect(await t.ops.retry('a')).toEqual({ status: 'ok' })
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('offline saat niat baru: gagal tanpa mengirim apa pun', async () => {
    const t = setup({ isOnline: () => false })
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'offline', code: 'OFFLINE', retryable: false } })
    expect(t.calls).toHaveLength(0)
  })

  it('galat tak terduga tidak membuat slot macet di fase sending', async () => {
    const t = setup()
    t.results.push(new Error('meledak'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'unexpected', retryable: false } })
    expect(t.ops.getItem('a').phase).toBe('failed')
    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
  })
})

describe('keadaan untuk pelanggan', () => {
  it('getItem stabil selama tidak berubah dan pelanggan diberi tahu saat berubah', async () => {
    const t = setup()
    expect(t.ops.getItem('x')).toBe(t.ops.getItem('x'))
    let hits = 0
    const off = t.ops.subscribe(() => {
      hits += 1
    })
    t.results.push(ok('op-1'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(hits).toBe(2)
    expect(t.ops.getItem('a')).toBe(t.ops.getItem('a'))
    off()
  })

  it('urutan hasil dikonfirmasi bertambah per sukses', async () => {
    const t = setup()
    t.results.push(ok('op-1'), ok('op-2'))
    await t.ops.run('a', 'session_set_status', P, 'satu')
    await t.ops.run('b', 'session_set_status', P, 'dua')
    expect(t.ops.getLast()).toEqual({ seq: 2, text: 'dua' })
  })
})
