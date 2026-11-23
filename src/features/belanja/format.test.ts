import { describe, expect, it } from 'vitest'
import { formatTimeJakarta } from '../daftar/format'
import { formatDateTimeJakarta } from './format'

describe('jam 24 Asia/Jakarta', () => {
  it('tengah malam tampil 00, bukan 24', () => {
    expect(formatTimeJakarta('2026-11-20T17:05:00Z')).toMatch(/^00[.:]05$/)
    expect(formatDateTimeJakarta('2026-11-20T17:05:00Z')).toMatch(/\b00[.:]05\b/)
    expect(formatDateTimeJakarta('2026-11-20T17:05:00Z')).not.toMatch(/24[.:]05/)
  })

  it('siang tetap 14.32 dan tanggal Jakarta ikut tampil', () => {
    const s = formatDateTimeJakarta('2026-11-20T07:32:00Z')
    expect(s).toMatch(/14[.:]32/)
    expect(s).toMatch(/20/)
    expect(s).toMatch(/2026/)
  })

  it('tanggal tidak valid tidak melempar galat', () => {
    expect(formatDateTimeJakarta('bukan tanggal')).toBe('-')
  })
})
