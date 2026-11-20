import { describe, expect, it } from 'vitest'
import { needsFetch, snapshotUrls, REFRESH_MARGIN_MS, type CacheEntry } from './photoUrlCache'

const NOW = 1_000_000
const cache = new Map<string, CacheEntry>([
  ['segar', { url: 'u1', expiresAt: NOW + 3_000_000 }],
  ['hampir', { url: 'u2', expiresAt: NOW + REFRESH_MARGIN_MS }],
  ['lewat', { url: 'u3', expiresAt: NOW - 1 }],
])

describe('photoUrlCache', () => {
  it('mengambil ulang yang belum ada, hampir habis, atau sudah habis, tanpa duplikat', () => {
    expect(needsFetch(cache, ['segar', 'hampir', 'lewat', 'baru', 'baru'], NOW)).toEqual(['hampir', 'lewat', 'baru'])
  })

  it('snapshot hanya memuat URL yang belum kedaluwarsa', () => {
    expect(snapshotUrls(cache, ['segar', 'hampir', 'lewat', 'baru'], NOW)).toEqual({ segar: 'u1', hampir: 'u2' })
  })
})
