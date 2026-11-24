import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({ blocking: vi.fn(), pending: vi.fn() }))
vi.mock('../../lib/queue', () => ({ countBlockingOps: mocks.blocking }))
vi.mock('../../lib/pending-ops', () => ({ countPendingOps: mocks.pending }))

import { checkEndLive, checkStartLive } from './sessionGuardsLive'

describe('penjaga langsung memakai countBlockingOps', () => {
  beforeEach(() => {
    mocks.blocking.mockReset()
    mocks.pending.mockReset()
  })

  it('akhir sesi: operasi yang sudah ditolak server (gagal, tidak menghalangi) tidak meminta konfirmasi', async () => {
    mocks.blocking.mockResolvedValue(0)
    mocks.pending.mockResolvedValue(3)
    const plan = await checkEndLive()
    expect(plan.needsConfirm).toBe(false)
    expect(mocks.blocking).toHaveBeenCalledTimes(1)
    expect(mocks.pending).not.toHaveBeenCalled()
  })

  it('akhir sesi: operasi menunggu atau gagal jaringan melewati batas meminta konfirmasi', async () => {
    mocks.blocking.mockResolvedValue(2)
    const plan = await checkEndLive()
    expect(plan.needsConfirm).toBe(true)
    expect(plan.message).toContain('2 perubahan')
  })

  it('mulai dan akhir memakai hitungan yang sama', async () => {
    mocks.blocking.mockResolvedValue(1)
    expect((await checkStartLive()).allowed).toBe(false)
    expect((await checkEndLive()).needsConfirm).toBe(true)
  })

  it('hitungan gagal dibaca dianggap tidak dapat diperiksa', async () => {
    mocks.blocking.mockRejectedValue(new Error('dexie'))
    expect((await checkStartLive()).allowed).toBe(false)
    expect((await checkEndLive()).needsConfirm).toBe(true)
  })
})
