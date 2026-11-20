import { useMemo, useState, type ReactNode } from 'react'
import { btnSecondary } from '../../components/ui'
import type { SyncState } from '../katalog/catalogSync'
import { formatTimeJakarta } from './format'
import { AddArea } from './AddArea'
import { EditableItemCard } from './EditableItemCard'
import { ListSummaryCard } from './ListSummaryCard'
import { usePhotoUrls } from './photoUrls'
import { useDaftar } from './useList'
import { useOnline } from './useOnline'

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
          Barang yang ditambahkan akan muncul di sini beserta estimasi biayanya. Gunakan tombol tambah di atas.
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
  const online = useOnline()
  const [feedback, setFeedback] = useState<string | null>(null)

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

      {feedback ? (
        <div
          role="status"
          className="flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ring-black/25"
        >
          <p className="min-w-0 break-words">{feedback}</p>
          <button
            type="button"
            className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
            onClick={() => setFeedback(null)}
          >
            Tutup
          </button>
        </div>
      ) : null}
      {view ? (
        <AddArea workspaceId={workspaceId} rows={view.rows} online={online} onFeedback={setFeedback} />
      ) : null}
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
                  <EditableItemCard
                    key={row.id}
                    row={row}
                    photoUrl={row.photoPath ? photoUrls[row.photoPath] : undefined}
                    catalogStatus={catalogSync.status}
                    workspaceId={workspaceId}
                    online={online}
                    onFeedback={setFeedback}
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
