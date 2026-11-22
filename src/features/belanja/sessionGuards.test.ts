import { describe, expect, it } from 'vitest'
import { OTHER_DEVICES_REMINDER, checkEnd, checkStart, planEnd, planStart } from './sessionGuards'

describe('planStart (FR-045)', () => {
  it('antrean kosong boleh mulai dan mengingatkan perangkat lain tanpa menyatakan mereka sudah sinkron', () => {
    const p = planStart(0)
    expect(p.allowed).toBe(true)
    expect(p.message).toBe(OTHER_DEVICES_REMINDER)
    expect(p.message).not.toMatch(/sudah (tersinkron|tersimpan)/i)
  })

  it('operasi yang menghalangi membatalkan mulai dan menyebut belum tersimpan di server', () => {
    const p = planStart(3)
    expect(p.allowed).toBe(false)
    expect(p.message).toContain('3 perubahan')
    expect(p.message).toContain('belum tersimpan di server')
  })

  it('antrean tidak dapat diperiksa tidak boleh dianggap kosong', () => {
    expect(planStart(null).allowed).toBe(false)
  })
})

describe('planEnd (FR-028, SYNC-012)', () => {
  it('tanpa perubahan tertunda tidak perlu konfirmasi', () => {
    expect(planEnd(0).needsConfirm).toBe(false)
  })

  it('dengan perubahan tertunda wajib konfirmasi dan menjelaskan konsekuensinya', () => {
    const p = planEnd(2)
    expect(p.needsConfirm).toBe(true)
    expect(p.message).toContain('2 perubahan')
    expect(p.message).toContain('tidak ikut dihitung')
    expect(p.message).toContain('ditandai gagal')
  })

  it('tidak dapat diperiksa wajib konfirmasi', () => {
    expect(planEnd(null).needsConfirm).toBe(true)
  })
})

describe('checkStart dan checkEnd', () => {
  it('galat saat menghitung dianggap tidak dapat diperiksa', async () => {
    const boom = async (): Promise<number> => {
      throw new Error('dexie')
    }
    expect((await checkStart(boom)).allowed).toBe(false)
    expect((await checkEnd(boom)).needsConfirm).toBe(true)
  })

  it('memakai hasil hitung', async () => {
    expect((await checkStart(async () => 0)).allowed).toBe(true)
    expect((await checkEnd(async () => 4)).needsConfirm).toBe(true)
  })
})
