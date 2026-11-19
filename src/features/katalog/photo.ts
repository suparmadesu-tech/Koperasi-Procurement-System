import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

const BUCKET = 'kps-photos'
const TTL_SECONDS = 3600
const REFRESH_MARGIN_MS = 60_000

const cache = new Map<string, { url: string; expiresAt: number }>()

function peek(path: string): string | null {
  const hit = cache.get(path)
  return hit && hit.expiresAt - Date.now() > REFRESH_MARGIN_MS ? hit.url : null
}

// Bucket privat: setiap tampilan memakai URL bertanda tangan berumur 1 jam.
export async function getSignedPhotoUrl(path: string): Promise<string> {
  const cached = peek(path)
  if (cached) return cached
  if (!supabase) throw new Error('Supabase belum dikonfigurasi.')
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, TTL_SECONDS)
  if (error || !data) throw error ?? new Error('URL foto tidak tersedia.')
  cache.set(path, { url: data.signedUrl, expiresAt: Date.now() + TTL_SECONDS * 1000 })
  return data.signedUrl
}

// Dipanggil saat keluar agar URL akun lama tidak tersisa di memori.
export function clearPhotoUrlCache() {
  cache.clear()
}

export type PhotoState =
  | { kind: 'none' }
  | { kind: 'loading' }
  | { kind: 'ready'; url: string }
  | { kind: 'offline' }
  | { kind: 'error' }

export function usePhotoUrl(path: string | null) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState<PhotoState>({ kind: path ? 'loading' : 'none' })

  useEffect(() => {
    if (!path) {
      setState({ kind: 'none' })
      return undefined
    }
    const cached = peek(path)
    if (cached) {
      setState({ kind: 'ready', url: cached })
      return undefined
    }
    let cancelled = false
    setState({ kind: 'loading' })
    getSignedPhotoUrl(path)
      .then((url) => {
        if (!cancelled) setState({ kind: 'ready', url })
      })
      .catch(() => {
        if (!cancelled) setState({ kind: navigator.onLine ? 'error' : 'offline' })
      })
    return () => {
      cancelled = true
    }
  }, [path, attempt])

  useEffect(() => {
    const retryOnline = () => setAttempt((n) => n + 1)
    window.addEventListener('online', retryOnline)
    return () => window.removeEventListener('online', retryOnline)
  }, [])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])
  // Gambar gagal dimuat biasanya karena URL kedaluwarsa atau offline.
  const reportImageError = useCallback(() => {
    if (path) cache.delete(path)
    setState({ kind: navigator.onLine ? 'error' : 'offline' })
  }, [path])

  return { state, retry, reportImageError }
}
