import { ListSummaryCard } from '../daftar/ListSummaryCard'
import { useDaftar } from '../daftar/useList'
import { CompletedSummary } from './CompletedSummary'
import type { CompletedView } from './sessionView'

// Dipasang hanya saat tidak ada sesi aktif, jadi langganan daftar dan katalog hanya hidup di keadaan ini.
export function NoSessionView({ workspaceId, completed }: { workspaceId: string; completed: CompletedView | null }) {
  const { view, readError, catalogSync } = useDaftar(workspaceId)
  const catalogPending = view !== null && view.rows.some((r) => r.unresolved) && catalogSync.status !== 'ok'

  return (
    <div className="space-y-4">
      {completed ? <CompletedSummary view={completed} /> : null}
      <section aria-labelledby="status-sesi" className="space-y-3">
        <h2 id="status-sesi" className="font-semibold">
          Belum ada sesi belanja yang aktif
        </h2>
        <p className="text-sm">Ringkasan daftar kebutuhan saat ini:</p>
        {readError !== null ? (
          <p role="alert" className="text-sm text-red-900">
            Daftar tidak dapat dibaca dari perangkat: {readError}
          </p>
        ) : view === null ? (
          <p role="status" className="text-sm">
            Membaca daftar dari perangkat...
          </p>
        ) : view.rows.length === 0 ? (
          <p className="text-sm">Daftar kebutuhan masih kosong.</p>
        ) : (
          <>
            {catalogPending ? (
              <p role="status" className="text-sm">
                Katalog belum termuat di perangkat, jadi sebagian harga belum dapat dihitung.
              </p>
            ) : null}
            <ListSummaryCard summary={view.summary} />
          </>
        )}
      </section>
    </div>
  )
}
