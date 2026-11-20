import { useEffect, useMemo, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { needsFetch, snapshotUrls, type CacheEntry } from './photoUrlCache'

// Sama dengan nama bucket di photoUpload.ts.
const BUCKET = 'kps-photos'
const TTL_SECONDS = 3600
const sb = supabase as unknown as SupabaseClient | null
const cache = new Map<string, CacheEntry>()

// refreshKey berubah setelah sinkronisasi, supaya foto yang gagal saat offline dicoba lagi.
export function usePhotoUrls(paths: string[], refreshKey: string | null): Record<string, string> {
  const key = useMemo(() => Array.from(new Set(paths)).sort().join('|'), [paths])
  const [version, setVersion] = useState(0)

  useEffect(() => {
    if (!sb || key === '') return undefined
    const missing = needsFetch(cache, key.split('|'), Date.now())
    if (missing.length === 0) return undefined
    let cancelled = false
    void (async () => {
      try {
        const { data, error } = await sb.storage.from(BUCKET).createSignedUrls(missing, TTL_SECONDS)
        if (error || !data || cancelled) return
        const expiresAt = Date.now() + TTL_SECONDS * 1000
        for (const row of data) {
          if (row.path && row.signedUrl && !row.error) cache.set(row.path, { url: row.signedUrl, expiresAt })
        }
        setVersion((v) => v + 1)
      } catch {
        // offline atau gagal: kartu menampilkan placeholder
      }
    })()
    return () => {
      cancelled = true
    }
  }, [key, refreshKey])

  // version memicu hitung ulang setelah cache terisi.
  return useMemo(() => snapshotUrls(cache, key === '' ? [] : key.split('|'), Date.now()), [key, version])
}
