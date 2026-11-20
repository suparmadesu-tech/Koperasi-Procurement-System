#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }
once() { [ "$(grep -cF -- "$2" "$1")" = "1" ] || fail "$1: pola harus tepat satu baris: $2"; }

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
for f in src/lib/db.ts src/lib/money.ts src/components/ui.ts src/pages/Daftar.tsx \
  src/auth/AuthProvider.tsx src/features/katalog/photoUpload.ts src/features/katalog/catalogSync.ts \
  src/features/daftar/types.ts src/features/daftar/listView.ts src/features/daftar/useList.ts \
  src/features/daftar/listSync.ts src/features/daftar/submitListOp.ts; do
  [ -f "$f" ] || fail "berkas tidak ada (Bagian 1 sudah dijalankan?): $f"
done
for f in DaftarView.tsx ListItemCard.tsx ListSummaryCard.tsx format.ts format.test.ts \
  photoUrls.ts photoUrlCache.ts photoUrlCache.test.ts; do
  [ ! -e "src/features/daftar/$f" ] || fail "src/features/daftar/$f sudah ada; tidak ditimpa"
done

need src/lib/db.ts 'declare listItems:'
need src/lib/db.ts 'this.version(3)'
need src/lib/money.ts 'export function formatRupiah('
need src/components/ui.ts 'export const btnSecondary'
need src/features/daftar/useList.ts 'export function useDaftar('
need src/features/daftar/listView.ts 'export function buildListView('
need src/features/daftar/listView.ts 'export const unpricedLabel'
need src/features/daftar/listView.ts 'export interface ListViewRow'
need src/features/daftar/listView.ts 'export interface ListSummary'
need src/features/katalog/catalogSync.ts 'export type SyncStatus'
need src/features/katalog/catalogSync.ts 'export interface SyncState'
need src/features/katalog/photoUpload.ts "const BUCKET = 'kps-photos'"
need src/auth/AuthProvider.tsx 'workspace: { id: string; name: string };'
need src/auth/AuthProvider.tsx 'export function useAuth('
once src/pages/Daftar.tsx "import Placeholder from './Placeholder';"
once src/pages/Daftar.tsx 'return <Placeholder title="Daftar"'
! grep -qF 'DaftarView' src/pages/Daftar.tsx || fail "src/pages/Daftar.tsx sudah memakai DaftarView"

# Pemeriksaan lunak: pembersihan data lokal saat keluar (FR-002).
if [ -f src/lib/local-data.ts ]; then
  grep -Eq 'delete|clear\(' src/lib/local-data.ts \
    || echo "PERINGATAN: src/lib/local-data.ts tidak tampak menghapus data lokal; periksa langkah verifikasi keluar."
else
  echo "PERINGATAN: src/lib/local-data.ts tidak ditemukan; periksa langkah verifikasi keluar."
fi

# --- Penulisan ---
cat > src/features/daftar/format.ts <<'EOF'
// "1.5" menjadi "1,5"; ribuan dipisah titik.
export function formatQuantity(q: string): string {
  const [int, frac] = q.split('.')
  const grouped = (int ?? '0').replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  return frac ? `${grouped},${frac}` : grouped
}

// Zona waktu tampilan Asia/Jakarta (FR-039).
export function formatTimeJakarta(iso: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(iso))
}
EOF

cat > src/features/daftar/format.test.ts <<'EOF'
import { describe, expect, it } from 'vitest'
import { formatQuantity, formatTimeJakarta } from './format'

describe('formatQuantity', () => {
  it('memakai koma desimal dan titik ribuan', () => {
    expect(formatQuantity('1.5')).toBe('1,5')
    expect(formatQuantity('0.001')).toBe('0,001')
    expect(formatQuantity('2')).toBe('2')
    expect(formatQuantity('1000')).toBe('1.000')
    expect(formatQuantity('1234567.25')).toBe('1.234.567,25')
  })
})

describe('formatTimeJakarta', () => {
  it('menampilkan jam Asia/Jakarta', () => {
    expect(formatTimeJakarta('2026-11-20T07:32:00Z')).toMatch(/14[.:]32/)
  })
})
EOF

cat > src/features/daftar/photoUrlCache.ts <<'EOF'
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
EOF

cat > src/features/daftar/photoUrlCache.test.ts <<'EOF'
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
EOF

cat > src/features/daftar/photoUrls.ts <<'EOF'
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
EOF

cat > src/features/daftar/ListSummaryCard.tsx <<'EOF'
import { formatRupiah } from '../../lib/money'
import { unpricedLabel, type ListSummary } from './listView'

export function ListSummaryCard({ summary }: { summary: ListSummary }) {
  return (
    <section aria-labelledby="ringkasan-estimasi" className="rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="ringkasan-estimasi" className="text-sm text-ink/75">
        Estimasi total
      </h2>
      <p className="text-2xl font-semibold">{formatRupiah(summary.total)}</p>
      <p className="text-sm">{summary.itemCount} barang</p>
      {summary.incomplete ? (
        <div className="mt-2 text-sm">
          <p className="font-semibold">Estimasi belum lengkap</p>
          <p>{unpricedLabel(summary.unpricedCount)}.</p>
        </div>
      ) : null}
      <p className="mt-2 text-xs text-ink/75">Memakai harga katalog saat ini, bukan harga saat belanja.</p>
    </section>
  )
}
EOF

cat > src/features/daftar/ListItemCard.tsx <<'EOF'
import { useState } from 'react'
import { formatRupiah } from '../../lib/money'
import type { SyncStatus } from '../katalog/catalogSync'
import { formatQuantity } from './format'
import type { ListViewRow } from './listView'

function ItemPhoto({ url, name }: { url: string | undefined; name: string }) {
  const [failed, setFailed] = useState(false)
  if (!url || failed) {
    return (
      <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-md bg-black/5 p-1 text-center text-xs text-ink/75">
        Foto belum termuat
      </div>
    )
  }
  return (
    <img
      src={url}
      alt={name}
      width={64}
      height={64}
      loading="lazy"
      decoding="async"
      onError={() => setFailed(true)}
      className="h-16 w-16 shrink-0 rounded-md object-cover"
    />
  )
}

export function ListItemCard({
  row,
  photoUrl,
  catalogStatus,
}: {
  row: ListViewRow
  photoUrl: string | undefined
  catalogStatus: SyncStatus
}) {
  return (
    <li className="flex gap-3 rounded-md bg-white p-3 ring-1 ring-black/20">
      {row.photoPath ? <ItemPhoto key={photoUrl ?? 'tanpa-url'} url={photoUrl} name={row.name} /> : null}
      <div className="min-w-0 flex-1 space-y-1">
        <p className="break-words font-semibold">{row.name}</p>
        <p className="text-sm">
          {formatQuantity(row.quantity)}
          {row.unitName ? ` ${row.unitName}` : ''}
          {row.archived ? <span className="ml-2 rounded-sm px-1.5 py-0.5 text-xs ring-1 ring-black/40">Diarsipkan</span> : null}
        </p>
        {row.note ? <p className="whitespace-pre-line break-words text-sm">Catatan: {row.note}</p> : null}
        {row.unresolved ? (
          <p className="text-xs text-ink/75">
            {catalogStatus === 'ok'
              ? 'Produk ini tidak ada di katalog.'
              : 'Katalog belum termuat; nama dan harga menyusul.'}
          </p>
        ) : null}
        {row.price !== null && row.subtotal !== null ? (
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
            <span>
              {formatRupiah(row.price)} × {formatQuantity(row.quantity)}
            </span>
            <span className="font-semibold">{formatRupiah(row.subtotal)}</span>
          </div>
        ) : (
          <p className="text-sm">Harga belum tersedia</p>
        )}
      </div>
    </li>
  )
}
EOF

cat > src/features/daftar/DaftarView.tsx <<'EOF'
import { useMemo, type ReactNode } from 'react'
import { btnSecondary } from '../../components/ui'
import type { SyncState } from '../katalog/catalogSync'
import { formatTimeJakarta } from './format'
import { ListItemCard } from './ListItemCard'
import { ListSummaryCard } from './ListSummaryCard'
import { usePhotoUrls } from './photoUrls'
import { useDaftar } from './useList'

function Notice({ alert, children }: { alert?: boolean; children: ReactNode }) {
  const tone = alert ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
  return (
    <div role={alert ? 'alert' : 'status'} className={`rounded-md bg-white p-3 text-sm ring-1 ${tone}`}>
      {children}
    </div>
  )
}

function syncLabel(sync: SyncState): string | null {
  if (sync.status === 'syncing') return 'Menyegarkan dari server...'
  if (sync.status === 'ok' && sync.lastSyncedAt) return `Diperbarui ${formatTimeJakarta(sync.lastSyncedAt)} WIB`
  return null
}

function EmptyState({ sync }: { sync: SyncState }) {
  if (sync.status === 'idle' || sync.status === 'syncing') {
    return <p role="status">Memeriksa daftar di server...</p>
  }
  if (sync.status === 'ok') {
    return (
      <section className="rounded-md bg-white p-4 ring-1 ring-black/20">
        <h2 className="font-semibold">Daftar kebutuhan masih kosong</h2>
        <p className="mt-1 text-sm">
          Barang yang ditambahkan akan muncul di sini beserta estimasi biayanya. Menambah barang belum tersedia dan
          menyusul di bagian berikutnya.
        </p>
      </section>
    )
  }
  return (
    <Notice>
      Tidak ada barang di daftar yang tersimpan di perangkat. Daftar di server bisa berbeda. Hubungkan ke internet
      lalu muat ulang.
    </Notice>
  )
}

export function DaftarView({ workspaceId }: { workspaceId: string }) {
  const { view, readError, sync, catalogSync, refresh } = useDaftar(workspaceId)
  const photoPaths = useMemo(
    () => (view ? view.rows.flatMap((r) => (r.photoPath ? [r.photoPath] : [])) : []),
    [view],
  )
  const photoUrls = usePhotoUrls(photoPaths, sync.lastSyncedAt)

  const label = syncLabel(sync)
  const busy = sync.status === 'syncing'

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold">Daftar kebutuhan</h1>
          {label ? <p className="text-sm text-ink/75">{label}</p> : null}
        </div>
        <button
          type="button"
          className={btnSecondary}
          onClick={refresh}
          disabled={busy || sync.status === 'offline'}
        >
          {busy ? 'Memuat...' : 'Muat ulang'}
        </button>
      </div>

      {readError !== null ? (
        <Notice alert>
          <p>Daftar tidak dapat dibaca dari penyimpanan perangkat: {readError}</p>
          <button type="button" className={`${btnSecondary} mt-3`} onClick={() => window.location.reload()}>
            Muat ulang halaman
          </button>
        </Notice>
      ) : view === null ? (
        <p role="status">Membaca daftar dari perangkat...</p>
      ) : (
        <>
          {sync.status === 'offline' ? (
            <Notice>
              Anda sedang offline. Daftar di bawah adalah data terakhir yang tersimpan di perangkat dan mungkin
              belum terbaru. Foto, penambahan, dan perubahan barang memerlukan koneksi internet.
            </Notice>
          ) : null}
          {sync.status === 'error' ? (
            <Notice alert>
              Daftar belum dapat disegarkan dari server. Menampilkan data terakhir di perangkat.
              {sync.error ? <span className="mt-1 block break-words text-xs">Rincian: {sync.error}</span> : null}
            </Notice>
          ) : null}
          {view.rows.length === 0 ? (
            <EmptyState sync={sync} />
          ) : (
            <>
              <ListSummaryCard summary={view.summary} />
              <ul className="space-y-3">
                {view.rows.map((row) => (
                  <ListItemCard
                    key={row.id}
                    row={row}
                    photoUrl={row.photoPath ? photoUrls[row.photoPath] : undefined}
                    catalogStatus={catalogSync.status}
                  />
                ))}
              </ul>
            </>
          )}
        </>
      )}
    </div>
  )
}
EOF

# --- Ubah src/pages/Daftar.tsx (pola harus cocok tepat satu kali) ---
python3 - <<'PY'
import sys
p = "src/pages/Daftar.tsx"
s = open(p, encoding="utf-8").read()

def sub(s, old, new):
    n = s.count(old)
    if n != 1:
        sys.exit("BERHENTI: pola cocok %d kali (harus 1): %r" % (n, old))
    return s.replace(old, new)

s = sub(s,
  "import Placeholder from './Placeholder';",
  "import { useAuth } from '../auth/AuthProvider';\nimport { DaftarView } from '../features/daftar/DaftarView';")
s = sub(s,
  '  return <Placeholder title="Daftar" note="Daftar kebutuhan belum tersedia. Dibuat di Tahap 3." />;',
  "  const { state } = useAuth();\n  if (state.status !== 'ready') return null;\n  return <DaftarView workspaceId={state.workspace.id} />;")
open(p, "w", encoding="utf-8").write(s)
PY

echo "Selesai. Jalankan: npx vitest run src/features/daftar && npm run build"