import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import { buildBulkReport, bulkConfirmMessage, bulkSummaryLine, createBulkBatch, type BulkConfig } from './bulkBatch'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})
const ITEMS = [
  { id: 'a', name: 'Apel' },
  { id: 'b', name: 'Beras' },
  { id: 'c', name: 'Cabai' },
]

// script: hasil per barang berurutan; barang tanpa script dianggap sukses.
function setup(script: Record<string, Array<ListOpResult | Error>> = {}, over: Partial<BulkConfig> = {}) {
  const calls: Array<{ itemId: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  let discards = 0
  let n = 0
  const batch = createBulkBatch({
    submit: async (_type, payload, options) => {
      const itemId = String(payload.item_id)
      calls.push({ itemId, payload, opId: options.opId })
      const next = script[itemId]?.shift()
      if (next instanceof Error) throw next
      return next ?? ok(options.opId ?? '')
    },
    newId: () => `op-${++n}`,
    isOnline: () => true,
    onDiscard: () => {
      discards += 1
    },
    ...over,
  })
  return { batch, calls, discards: () => discards }
}

async function start(t: ReturnType<typeof setup>, items = ITEMS) {
  t.batch.open(items)
  await t.batch.confirm()
}

describe('urutan dan op_id per barang', () => {
  it('semua berhasil: satu session_set_status per barang, berurutan, op_id berbeda', async () => {
    const t = setup()
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'c'])
    expect(new Set(t.calls.map((c) => c.opId)).size).toBe(3)
    expect(t.calls.every((c) => c.payload.status === 'purchased')).toBe(true)
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    expect(buildBulkReport(s)).toMatchObject({ total: 3, ok: 3, unprocessed: 0, uncertain: false, rejected: [] })
  })

  it('dialog konfirmasi menyebut jumlah barang dan belum mengirim apa pun', () => {
    const t = setup()
    t.batch.open(ITEMS)
    expect(t.batch.getState().phase).toBe('confirm')
    expect(t.batch.getState().entries).toHaveLength(3)
    expect(t.calls).toHaveLength(0)
    expect(bulkConfirmMessage(3)).toContain('3 barang di keranjang')
  })
})

describe('penolakan tidak menghentikan batch (SYNC-003)', () => {
  it('batch lanjut setelah satu barang ditolak, dan laporan menyebut nama dan alasan', async () => {
    const t = setup({ b: [bad('x', 'KPS_ITEM_DELETED', false)] })
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'c'])
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    const r = buildBulkReport(s)
    expect(r.ok).toBe(2)
    expect(r.unprocessed).toBe(0)
    expect(r.rejected).toEqual([{ id: 'b', name: 'Beras', code: 'KPS_ITEM_DELETED', message: 'pesan KPS_ITEM_DELETED' }])
    expect(bulkSummaryLine(r)).toBe('2 berhasil di server, 1 ditolak, 0 belum diproses.')
  })

  it('semua ditolak: batch tetap selesai dan melaporkan semuanya', async () => {
    const rej = () => [bad('x', 'KPS_SESSION_NOT_ACTIVE', false)]
    const t = setup({ a: rej(), b: rej(), c: rej() })
    await start(t)
    expect(t.calls).toHaveLength(3)
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 0, unprocessed: 0 })
    expect(buildBulkReport(t.batch.getState()).rejected).toHaveLength(3)
  })
})

describe('jaringan gagal menghentikan batch dan retry memakai op_id lama (SYNC-004)', () => {
  it('berhenti pada barang yang gagal; sisanya belum diproses; barang itu belum pasti', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b'])
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('network')
    const r = buildBulkReport(s)
    expect(r).toMatchObject({ ok: 1, unprocessed: 2, uncertain: true })
    expect(bulkSummaryLine(r)).toContain('1 berhasil di server, 0 ditolak, 2 belum diproses.')
    expect(bulkSummaryLine(r)).toContain('mungkin sudah tersimpan')
  })

  it('retry mengirim ulang barang yang gagal dengan op_id yang sama, lalu melanjutkan sisanya tanpa pengiriman ganda', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    await t.batch.retry()
    expect(t.calls.map((c) => `${c.itemId}:${c.opId}`)).toEqual(['a:op-1', 'b:op-2', 'b:op-2', 'c:op-3'])
    expect(t.batch.getState().phase).toBe('done')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 3, unprocessed: 0, uncertain: false })
  })

  it('retry yang gagal lagi tetap memakai op_id yang sama', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true), bad('x', 'NETWORK', true)] })
    await start(t)
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('halted')
    expect(t.calls.filter((c) => c.itemId === 'b').map((c) => c.opId)).toEqual(['op-2', 'op-2'])
  })

  it('penolakan setelah retry tetap tercatat dan batch lanjut', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true), bad('x', 'KPS_ITEM_DELETED', false)] })
    await start(t)
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('done')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 2, unprocessed: 0 })
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'b', 'c'])
  })

  it('menghentikan batch: sisa tidak diproses, layar disegarkan, dan laporan tetap jujur', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    t.batch.discard()
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    expect(s.discarded).toBe(true)
    expect(t.discards()).toBe(1)
    expect(buildBulkReport(s)).toMatchObject({ ok: 1, unprocessed: 2, uncertain: true, discarded: true })
    expect(t.calls).toHaveLength(2)
  })
})

describe('offline, sesi berakhir, dan galat tak terduga', () => {
  it('offline di tengah batch: berhenti sebelum mengirim barang berikutnya, retry diabaikan sampai online', async () => {
    let online = true
    const t = setup({}, {
      isOnline: () => online,
      submit: async (_t, payload, options) => {
        if (payload.item_id === 'a') online = false
        return ok(options.opId ?? '')
      },
    })
    await start(t)
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('offline')
    expect(buildBulkReport(s)).toMatchObject({ ok: 1, unprocessed: 2, uncertain: false })

    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('halted')
    online = true
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('done')
  })

  it('SESSION_EXPIRED menghentikan batch, bukan menolak tiap barang', async () => {
    const t = setup({ a: [bad('x', 'SESSION_EXPIRED', false)] })
    await start(t)
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('session')
    expect(t.calls).toHaveLength(1)
    expect(buildBulkReport(s)).toMatchObject({ ok: 0, unprocessed: 3, uncertain: false })
  })

  it('galat tak terduga tidak membuat batch macet di fase running', async () => {
    const t = setup({ b: [new Error('meledak')] })
    await start(t)
    expect(t.batch.getState().phase).toBe('halted')
    expect(t.batch.getState().halt?.kind).toBe('unexpected')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 1, unprocessed: 2 })
  })
})

describe('kunci dan siklus', () => {
  it('konfirmasi berganda hanya menjalankan satu batch', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: string[] = []
    const t = setup({}, {
      submit: async (_t, payload, options) => {
        sent.push(String(payload.item_id))
        return payload.item_id === 'a' ? gate : ok(options.opId ?? '')
      },
    })
    t.batch.open(ITEMS)
    const p1 = t.batch.confirm()
    const p2 = t.batch.confirm()
    const p3 = t.batch.confirm()
    expect(t.batch.getState().phase).toBe('running')
    release(ok('op-1'))
    await Promise.all([p1, p2, p3])
    expect(sent).toEqual(['a', 'b', 'c'])
  })

  it('open diabaikan saat berjalan atau tertahan, kosong, atau offline', async () => {
    const t = setup({ a: [bad('x', 'NETWORK', true)] })
    t.batch.open([])
    expect(t.batch.getState().phase).toBe('idle')
    await start(t)
    t.batch.open(ITEMS)
    expect(t.batch.getState().phase).toBe('halted')
    const off = setup({}, { isOnline: () => false })
    off.batch.open(ITEMS)
    expect(off.batch.getState().phase).toBe('idle')
  })

  it('membatalkan di dialog tidak mengirim apa pun; tidak dapat dibatalkan saat berjalan', async () => {
    const t = setup()
    t.batch.open(ITEMS)
    t.batch.cancel()
    expect(t.batch.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
    await t.batch.confirm()
    expect(t.calls).toHaveLength(0)
  })

  it('selesai lalu ditutup; batch baru memakai op_id baru', async () => {
    const t = setup()
    await start(t, [ITEMS[0]!])
    t.batch.close()
    expect(t.batch.getState().phase).toBe('idle')
    await start(t, [ITEMS[1]!])
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('pelanggan diberi tahu pada tiap perubahan dan getState stabil', async () => {
    const t = setup()
    let hits = 0
    t.batch.subscribe(() => {
      hits += 1
    })
    await start(t, [ITEMS[0]!])
    expect(hits).toBeGreaterThanOrEqual(3)
    expect(t.batch.getState()).toBe(t.batch.getState())
  })
})
