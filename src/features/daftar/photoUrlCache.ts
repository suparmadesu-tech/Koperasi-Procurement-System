export interface CacheEntry {
  url: string
  expiresAt: number
}

// URL bertanda tangan diambil ulang bila sisa umurnya kurang dari ini.
export const REFRESH_MARGIN_MS = 5 * 60 * 1000

export function needsFetch(cache: ReadonlyMap<string, CacheEntry>, paths: string[], now: number): string[] {
  const out: string[] = []
  for (const p of new Set(paths)) {
    const e = cache.get(p)
    if (!e || e.expiresAt - now <= REFRESH_MARGIN_MS) out.push(p)
  }
  return out
}

export function snapshotUrls(
  cache: ReadonlyMap<string, CacheEntry>,
  paths: string[],
  now: number,
): Record<string, string> {
  const out: Record<string, string> = {}
  for (const p of paths) {
    const e = cache.get(p)
    if (e && e.expiresAt > now) out[p] = e.url
  }
  return out
}
