import { useSyncExternalStore } from 'react'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { buildBulkReport, bulkConfirmMessage, bulkSummaryLine, type BulkItem } from './bulkBatch'
import type { Checklist } from './useChecklist'

// Dipasang di tingkat sesi, bukan di dalam kelompok "Di keranjang": kelompok itu hilang saat semua barang sudah dibeli,
// padahal laporan batch harus tetap terlihat.
export function BulkPurchase({
  checklist,
  items,
  online,
}: {
  checklist: Checklist
  items: BulkItem[]
  online: boolean
}) {
  const { bulk, items: itemOps } = checklist
  const state = useSyncExternalStore(bulk.subscribe, bulk.getState, bulk.getState)
  const itemBusy = useSyncExternalStore(itemOps.subscribe, itemOps.anyBusy, itemOps.anyBusy)
  const phase = state.phase
  if (phase === 'idle' && items.length === 0) return null

  const report = buildBulkReport(state)
  const processed = report.ok + report.rejected.length
  const current = state.entries[state.cursor]
  const showButton = (phase === 'idle' || phase === 'done') && items.length > 0
  const reason = !online
    ? 'Anda sedang offline. Aksi massal memerlukan koneksi internet.'
    : itemBusy
      ? 'Menunggu perubahan barang yang sedang disimpan.'
      : null

  return (
    <section aria-labelledby="aksi-massal" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="aksi-massal" className="font-semibold">
        Aksi massal
      </h2>

      {showButton ? (
        <>
          <button
            type="button"
            className={btnPrimary}
            onClick={() => bulk.open(items)}
            disabled={reason !== null}
          >
            Tandai semua isi keranjang sebagai dibeli
          </button>
          {reason ? <p className="text-sm">{reason}</p> : null}
        </>
      ) : null}

      {phase === 'running' ? (
        <p role="status" className="text-sm">
          Memproses {processed + 1} dari {report.total}
          {current ? `: ${current.name}` : ''}. Setiap barang dikonfirmasi server satu per satu.
        </p>
      ) : null}

      {phase === 'halted' && state.halt ? (
        <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
          <p className="break-words">{state.halt.message}</p>
          <p>{bulkSummaryLine(report)}</p>
          {report.rejected.length > 0 ? (
            <ul className="list-disc space-y-1 pl-5">
              {report.rejected.map((r) => (
                <li key={r.id} className="break-words">
                  <span className="font-semibold">{r.name}</span>: {r.message}
                </li>
              ))}
            </ul>
          ) : null}
          <p className="text-xs">
            Mengirim ulang aman dan tidak menggandakan hasil. Bila dihentikan, sisa barang tidak diproses dan layar
            disegarkan dari server.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={() => void bulk.retry()} disabled={!online}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={() => bulk.discard()}>
              Hentikan
            </button>
          </div>
        </div>
      ) : null}

      {phase === 'done' ? (
        <div
          role={report.rejected.length > 0 || report.discarded ? 'alert' : 'status'}
          className="space-y-2 rounded-md bg-white p-3 text-sm ring-1 ring-black/25"
        >
          <p>{bulkSummaryLine(report)}</p>
          {report.discarded ? <p>Pemrosesan dihentikan. Layar disegarkan dari server.</p> : null}
          {report.rejected.length > 0 ? (
            <ul className="list-disc space-y-1 pl-5">
              {report.rejected.map((r) => (
                <li key={r.id} className="break-words">
                  <span className="font-semibold">{r.name}</span>: {r.message}
                </li>
              ))}
            </ul>
          ) : null}
          <button type="button" className={btnSecondary} onClick={() => bulk.close()}>
            Tutup laporan
          </button>
        </div>
      ) : null}

      <ConfirmDialog
        open={phase === 'confirm'}
        title="Tandai semua isi keranjang sebagai dibeli?"
        message={bulkConfirmMessage(state.entries.length)}
        confirmLabel={`Tandai ${state.entries.length} barang`}
        cancelLabel="Batal"
        onConfirm={() => void bulk.confirm()}
        onCancel={() => bulk.cancel()}
      />
    </section>
  )
}
