import { useMemo, type ReactNode } from 'react'
import { btnSecondary } from '../../components/ui'
import { formatTimeJakarta } from '../daftar/format'
import { usePhotoUrls } from '../daftar/photoUrls'
import type { SyncState } from '../katalog/catalogSync'
import { ActiveSession } from './ActiveSession'
import { FlowNoticeBanner } from './FlowNoticeBanner'
import { NoSessionView } from './NoSessionView'
import { buildActiveView, buildCompletedView } from './sessionView'
import { useSessionState } from './useSessions'

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
  if (sync.status === 'ok' && sync.lastSyncedAt) return `Data dari server pukul ${formatTimeJakarta(sync.lastSyncedAt)} WIB`
  return null
}

export function BelanjaView({ workspaceId }: { workspaceId: string }) {
  const { state, readError, sync, refresh } = useSessionState(workspaceId)

  const activeView = useMemo(
    () => (state && state.active ? buildActiveView(state.active, state.activeItems) : null),
    [state],
  )
  const completed = useMemo(() => (state ? buildCompletedView(state.lastEnded, state.lastEndedItems) : null), [state])
  const photoPaths = useMemo(
    () =>
      activeView
        ? activeView.groups.flatMap((g) => g.items.flatMap((i) => (i.photoPath ? [i.photoPath] : [])))
        : [],
    [activeView],
  )
  const photoUrls = usePhotoUrls(photoPaths, sync.lastSyncedAt)

  const label = syncLabel(sync)
  const busy = sync.status === 'syncing'
  // Tanpa data lokal dan sinkronisasi pertama belum selesai, "tanpa sesi" belum boleh disimpulkan.
  const checking =
    state !== null &&
    state.active === null &&
    sync.lastSyncedAt === null

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold">Belanja</h1>
          {label ? <p className="text-sm text-ink/75">{label}</p> : null}
          <p className="text-xs text-ink/75">
            Perubahan dari perangkat lain tampil setelah data disegarkan. Layar ini tidak dapat memastikan perangkat
            lain sudah tersinkron.
          </p>
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

      <FlowNoticeBanner />

      {readError !== null ? (
        <Notice alert>
          <p>Data sesi tidak dapat dibaca dari penyimpanan perangkat: {readError}</p>
          <button type="button" className={`${btnSecondary} mt-3`} onClick={() => window.location.reload()}>
            Muat ulang halaman
          </button>
        </Notice>
      ) : state === null ? (
        <p role="status">Membaca data sesi dari perangkat...</p>
      ) : (
        <>
          {sync.status === 'offline' ? (
            <Notice>
              Anda sedang offline. Layar menampilkan data sesi yang terakhir tersimpan di perangkat. Sesi di server
              mungkin sudah berubah.
            </Notice>
          ) : null}
          {sync.status === 'error' ? (
            <Notice alert>
              Data sesi belum dapat disegarkan dari server. Menampilkan data terakhir di perangkat.
              {sync.error ? <span className="mt-1 block break-words text-xs">Rincian: {sync.error}</span> : null}
            </Notice>
          ) : null}
          {checking ? (
            <p role="status">
              {sync.status === 'offline' || sync.status === 'error'
                ? 'Belum dapat memeriksa sesi belanja di server. Sesi aktif mungkin ada. Sambungkan internet lalu muat ulang.'
                : 'Memeriksa sesi belanja di server...'}
            </p>
          ) : activeView && state.active ? (
            <ActiveSession
              view={activeView}
              photoUrls={photoUrls}
              workspaceId={workspaceId}
              sessionId={state.active.id}
              items={state.activeItems}
            />
          ) : (
            <NoSessionView workspaceId={workspaceId} completed={completed} />
          )}
        </>
      )}
    </div>
  )
}
