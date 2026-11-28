import { describe, expect, it } from 'vitest'
import type { PhotoFlowDeps } from '../daftar/photoFlow'
import type { ListOpResult } from '../daftar/types'
import {
  addDoneMessage,
  addDoneTone,
  createSessionAdd,
  isSessionLevelCode,
  type AddConfig,
  type AddIntent,
  type AddPhase,
  type AddSettled,
} from './sessionAdd'

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

type ManualIntent = Extract<AddIntent, { kind: 'manual' }>
const catalog: AddIntent = { kind: 'catalog', productId: 'p1', name: 'Gula', quantity: '2', note: null }
const manual = (over: Partial<ManualIntent> = {}): ManualIntent => ({
  kind: 'manual',
  name: 'Plastik',
  unit: 'pak',
  quantity: '1.5',
  note: null,
  file: null,
  ...over,
})

function setup(over: Partial<AddConfig> = {}) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  const settled: AddSettled[] = []
  const mode = { compress: 'ok' as 'ok' | 'bad', upload: 'ok' as 'ok' | 'fail' }
  const counts = { compress: 0, upload: 0 }
  let op = 0
  let item = 0
  let discards = 0
  const blob = new Blob(['x'])
  const file = blob as unknown as File
  const photo: PhotoFlowDeps = {
    compress: async () => {
      counts.compress += 1
      return mode.compress === 'ok'
        ? { ok: true, data: { blob, mime: 'image/webp' } }
        : { ok: false, error: { code: 'PHOTO_TOO_LARGE', message: 'Foto terlalu besar.' } }
    },
    upload: async () => {
      counts.upload += 1
      return mode.upload === 'ok'
        ? { ok: true, data: `w1/foto-${counts.upload}.webp` }
        : { ok: false, error: { code: 'UPLOAD_FAILED', message: 'Tidak ada koneksi internet.' } }
    },
  }
  const add = createSessionAdd({
    workspaceId: 'w1',
    sessionId: 's1',
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    newId: () => `op-${++op}`,
    newItemId: () => `item-${++item}`,
    isOnline: () => true,
    photo,
    onDiscard: () => {
      discards += 1
    },
    onSettled: (o) => {
      settled.push(o)
    },
    ...over,
  })
  return { add, calls, results, settled, mode, counts, file, discards: () => discards }
}

describe('tambah barang katalog (FR-052, T-04)', () => {
  it('mengirim kps_add_catalog_to_session dengan payload sesi; id barang dari server; tanpa baris lokal', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'srv-9', price_snapshot: 5000 }))
    const done = await t.add.submit({ ...catalog, note: 'merah' } as AddIntent)
    expect(t.calls).toEqual([
      {
        type: 'kps_add_catalog_to_session',
        payload: { session_id: 's1', product_id: 'p1', quantity: 2, note: 'merah' },
        opId: 'op-1',
      },
    ])
    expect(done).toMatchObject({ kind: 'catalog', name: 'Gula', itemId: 'srv-9', photo: 'none' })
    expect(t.add.getState().phase).toBe('done')
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
  })

  it('produk yang sama ditambahkan dua kali: dua operasi terpisah, tidak digabung atau diblokir (T-D)', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'a' }), ok('op-2', { item_id: 'b' }))
    await t.add.submit(catalog)
    await t.add.submit(catalog)
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
    expect(t.calls.map((c) => c.payload.product_id)).toEqual(['p1', 'p1'])
  })

  it('catatan kosong tidak dikirim', async () => {
    const t = setup()
    t.results.push(ok('op-1'))
    await t.add.submit(catalog)
    expect(t.calls[0]?.payload).toEqual({ session_id: 's1', product_id: 'p1', quantity: 2 })
  })
})

describe('tambah barang manual (FR-052)', () => {
  it('mengirim session_add_manual dengan id dari klien tanpa foto', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual())
    expect(t.calls).toEqual([
      {
        type: 'session_add_manual',
        payload: { session_id: 's1', id: 'item-1', name: 'Plastik', unit: 'pak', quantity: 1.5 },
        opId: 'op-1',
      },
    ])
    expect(done).toMatchObject({ kind: 'manual', itemId: 'item-1', photo: 'none' })
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
  })

  it('foto berhasil diunggah: path baru ikut dikirim dan hasil menyebut foto terpasang setelah konfirmasi server', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual({ file: t.file }))
    expect(t.calls[0]?.payload).toMatchObject({ id: 'item-1', photo_path: 'w1/foto-1.webp' })
    expect(done?.photo).toBe('attached')
    expect(addDoneMessage(done!)).toContain('dengan foto (dikonfirmasi server)')
  })
})

describe('foto gagal tetap menambah barang tanpa foto (FR-013, SYNC-019)', () => {
  it('unggah gagal: barang tetap dikirim tanpa photo_path, hasil kompres disimpan, dan pesan jujur', async () => {
    const t = setup()
    t.mode.upload = 'fail'
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual({ file: t.file }))
    expect(t.calls).toHaveLength(1)
    expect('photo_path' in (t.calls[0]?.payload ?? {})).toBe(false)
    expect(done).toMatchObject({ photo: 'failed', itemId: 'item-1', photoMessage: 'Tidak ada koneksi internet.' })
    expect(done?.pending?.mime).toBe('image/webp')
    const msg = addDoneMessage(done!)
    expect(msg).toContain('tanpa foto')
    expect(msg).toContain('Foto belum terpasang')
    expect(msg).not.toContain('dengan foto')
    expect(addDoneTone(done!)).toBe('error')
  })

  it('foto tidak dapat diproses (kompres gagal): tidak ada yang diunggah atau dikirim', async () => {
    const t = setup()
    t.mode.compress = 'bad'
    const done = await t.add.submit(manual({ file: t.file }))
    expect(done).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'photo', message: 'Foto terlalu besar.', retryable: false })
    expect(t.counts).toEqual({ compress: 1, upload: 0 })
    expect(t.calls).toHaveLength(0)

    t.mode.compress = 'ok'
    t.results.push(ok('op-1'))
    expect(await t.add.submit(manual({ file: t.file }))).not.toBeNull()
    expect(t.calls).toHaveLength(1)
  })
})

describe('kirim ulang dengan op_id dan id barang yang sama (SYNC-004)', () => {
  it('retry mengirim op_id, id barang, dan path foto yang sama; foto tidak diunggah ulang', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-1', { item_id: 'item-1' }))
    const first = await t.add.submit(manual({ file: t.file }))
    expect(first).toBeNull()
    expect(t.add.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.add.hasPending()).toBe(true)

    const done = await t.add.retry()
    expect(done).toMatchObject({ itemId: 'item-1', photo: 'attached' })
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.calls[0]).toMatchObject({ opId: 'op-1', payload: { id: 'item-1', photo_path: 'w1/foto-1.webp' } })
    expect(t.counts).toEqual({ compress: 1, upload: 1 })
    expect(t.add.hasPending()).toBe(false)
  })

  it('retry katalog memakai op_id dan payload yang sama', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-1', { item_id: 'srv' }))
    await t.add.submit(catalog)
    await t.add.retry()
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
  })

  it('retry yang gagal lagi tetap memakai op_id dan id yang sama', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), bad('x', 'NETWORK', true))
    await t.add.submit(manual())
    await t.add.retry()
    expect(t.add.getState().phase).toBe('failed')
    expect(t.calls.map((c) => `${c.opId}:${String(c.payload.id)}`)).toEqual(['op-1:item-1', 'op-1:item-1'])
  })

  it('selama percobaan menunggu, niat baru diabaikan: tidak ada op_id atau id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true))
    await t.add.submit(manual())
    expect(await t.add.submit(manual({ name: 'Lain' }))).toBeNull()
    expect(t.calls).toHaveLength(1)
  })

  it('retry saat offline tidak memanggil pengirim dan percobaan tetap tersimpan', async () => {
    let online = true
    const t = setup({ isOnline: () => online })
    t.results.push(bad('x', 'NETWORK', true), ok('op-1'))
    await t.add.submit(catalog)
    online = false
    expect(await t.add.retry()).toBeNull()
    expect(t.calls).toHaveLength(1)
    expect(t.add.getState().phase).toBe('failed')
    online = true
    expect(await t.add.retry()).not.toBeNull()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan niat berikutnya memakai op_id dan id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-2'))
    await t.add.submit(manual())
    t.add.dismiss()
    expect(t.add.getState().phase).toBe('idle')
    expect(t.discards()).toBe(1)
    await t.add.submit(manual())
    expect(t.calls.map((c) => `${c.opId}:${String(c.payload.id)}`)).toEqual(['op-1:item-1', 'op-2:item-2'])
  })
})

describe('tanpa pengiriman ganda', () => {
  it('kirim berganda pada niat yang sama hanya mengirim satu operasi', async () => {
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
    const p1 = t.add.submit(manual())
    const p2 = t.add.submit(manual())
    const p3 = t.add.submit(catalog)
    expect(t.add.getState().phase).toBe('sending')
    release(ok('op-1', { item_id: 'item-1' }))
    const out = await Promise.all([p1, p2, p3])
    expect(out[0]).not.toBeNull()
    expect(out[1]).toBeNull()
    expect(out[2]).toBeNull()
    expect(sent).toEqual(['op-1'])
  })

  it('kirim berganda saat foto diproses juga hanya satu niat', async () => {
    let releaseUpload!: () => void
    const uploadGate = new Promise<void>((res) => {
      releaseUpload = res
    })
    const blob = new Blob(['x'])
    const t = setup({
      photo: {
        compress: async () => ({ ok: true, data: { blob, mime: 'image/webp' } }),
        upload: async () => {
          await uploadGate
          return { ok: true, data: 'w1/a.webp' }
        },
      },
    })
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const p1 = t.add.submit(manual({ file: blob as unknown as File }))
    const p2 = t.add.submit(manual({ file: blob as unknown as File }))
    expect(t.add.getState().phase).toBe('preparing')
    releaseUpload()
    await Promise.all([p1, p2])
    expect(t.calls).toHaveLength(1)
  })
})

describe('penolakan tidak dicoba ulang (SYNC-020)', () => {
  it('KPS_PRODUCT_ARCHIVED: tidak dapat diulang; niat baru memakai op_id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_PRODUCT_ARCHIVED', false), ok('op-2', { item_id: 'b' }))
    expect(await t.add.submit(catalog)).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'rejected', code: 'KPS_PRODUCT_ARCHIVED', retryable: false })
    expect(t.add.hasPending()).toBe(false)
    expect(await t.add.retry()).toBeNull()
    expect(t.calls).toHaveLength(1)
    expect(await t.add.submit(catalog)).not.toBeNull()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('penolakan barang manual: id baru untuk niat berikutnya', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_TEXT_TOO_LONG', false), ok('op-2'))
    await t.add.submit(manual())
    await t.add.submit(manual())
    expect(t.calls.map((c) => String(c.payload.id))).toEqual(['item-1', 'item-2'])
  })

  it('kode sesi-level dipisahkan dari penolakan yang dapat diperbaiki di formulir', () => {
    expect(isSessionLevelCode('KPS_SESSION_NOT_ACTIVE')).toBe(true)
    expect(isSessionLevelCode('SESSION_EXPIRED')).toBe(true)
    for (const c of ['KPS_PRODUCT_ARCHIVED', 'KPS_FRACTION_NOT_ALLOWED', 'KPS_INVALID_QUANTITY', 'KPS_TEXT_TOO_LONG', 'KPS_CONFLICT', 'KPS_PHOTO_NOT_FOUND', 'KPS_INVALID_PHOTO_PATH']) {
      expect(isSessionLevelCode(c)).toBe(false)
    }
  })

  it('hasil akhir dilaporkan lewat onSettled: penolakan dan sukses', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_SESSION_NOT_ACTIVE', false), ok('op-2', { item_id: 'b' }))
    await t.add.submit(catalog)
    await t.add.submit(catalog)
    expect(t.settled[0]).toMatchObject({ ok: false, failure: { kind: 'rejected', code: 'KPS_SESSION_NOT_ACTIVE' } })
    expect(t.settled[1]).toMatchObject({ ok: true, done: { itemId: 'b' } })
  })
})

describe('offline, galat tak terduga, dan fase', () => {
  it('offline: gagal tanpa memproses foto atau mengirim apa pun', async () => {
    const t = setup({ isOnline: () => false })
    const out = await t.add.submit(manual({ file: t.file }))
    expect(out).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'offline', code: 'OFFLINE', retryable: false })
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
    expect(t.calls).toHaveLength(0)
  })

  it('galat tak terduga tidak membuat pengendali macet di fase sending', async () => {
    const t = setup()
    t.results.push(new Error('meledak'))
    expect(await t.add.submit(catalog)).toBeNull()
    expect(t.add.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'unexpected', retryable: false } })
    t.add.dismiss()
    expect(t.add.getState().phase).toBe('idle')
  })

  it('urutan fase barang manual dengan foto', async () => {
    const t = setup()
    const phases: AddPhase[] = []
    t.add.subscribe(() => phases.push(t.add.getState().phase))
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    await t.add.submit(manual({ file: t.file }))
    expect(phases).toEqual(['preparing', 'sending', 'done'])
  })

  it('id barang manual jatuh ke id klien bila server tidak mengirim item_id', async () => {
    const t = setup()
    t.results.push(ok('op-1', {}))
    const done = await t.add.submit(manual())
    expect(done?.itemId).toBe('item-1')
  })
})

describe('teks hasil', () => {
  it('selalu menyebut dikonfirmasi server dan bahwa estimasi awal tidak berubah (BR-025)', () => {
    const base = { name: 'Gula', itemId: 'i', photoMessage: null, pending: null }
    for (const d of [
      { ...base, kind: 'catalog' as const, photo: 'none' as const },
      { ...base, kind: 'manual' as const, photo: 'none' as const },
      { ...base, kind: 'manual' as const, photo: 'attached' as const },
      { ...base, kind: 'manual' as const, photo: 'failed' as const },
    ]) {
      const m = addDoneMessage(d)
      expect(m).toContain('dikonfirmasi server')
      expect(m).toContain('Estimasi awal sesi tidak berubah.')
    }
  })
})
