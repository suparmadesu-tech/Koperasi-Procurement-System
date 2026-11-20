import { describe, expect, it } from 'vitest'
import { createAttemptRunner } from './attemptRunner'
import type { ListOpResult } from './types'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code: 'X',
  message: 'pesan',
  retryable,
})

function setup(results: ListOpResult[]) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  let n = 0
  const runner = createAttemptRunner(
    async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      return r
    },
    () => `op-${++n}`,
  )
  return { runner, calls }
}

describe('createAttemptRunner', () => {
  it('sukses tidak menyisakan percobaan', async () => {
    const { runner, calls } = setup([ok('op-1')])
    await runner.run('list_delete', { item_id: 'i1' })
    expect(runner.hasPending()).toBe(false)
    expect(calls[0]).toEqual({ type: 'list_delete', payload: { item_id: 'i1' }, opId: 'op-1' })
  })

  it('gagal retryable dikirim ulang dengan opId dan payload yang sama', async () => {
    const { runner, calls } = setup([bad('op-1', true), ok('op-1')])
    await runner.run('list_set_quantity', { item_id: 'i1', quantity: 2 })
    expect(runner.hasPending()).toBe(true)
    const r = await runner.retry()
    expect(r?.ok).toBe(true)
    expect(runner.hasPending()).toBe(false)
    expect(calls).toHaveLength(2)
    expect(calls[1]).toEqual(calls[0])
  })

  it('retry yang gagal lagi tetap memakai opId yang sama', async () => {
    const { runner, calls } = setup([bad('op-1', true), bad('op-1', true)])
    await runner.run('list_delete', { item_id: 'i1' })
    await runner.retry()
    expect(runner.hasPending()).toBe(true)
    expect(calls[1]?.opId).toBe('op-1')
  })

  it('gagal tidak retryable membersihkan percobaan dan retry tidak mengirim apa pun', async () => {
    const { runner, calls } = setup([bad('op-1', false)])
    await runner.run('list_delete', { item_id: 'i1' })
    expect(runner.hasPending()).toBe(false)
    expect(await runner.retry()).toBeNull()
    expect(calls).toHaveLength(1)
  })

  it('discard membuang percobaan dan operasi berikutnya memakai opId baru', async () => {
    const { runner, calls } = setup([bad('op-1', true), ok('op-2')])
    await runner.run('list_delete', { item_id: 'i1' })
    runner.discard()
    expect(runner.hasPending()).toBe(false)
    await runner.run('list_delete', { item_id: 'i2' })
    expect(calls[1]?.opId).toBe('op-2')
  })
})
