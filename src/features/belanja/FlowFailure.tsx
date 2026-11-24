import { btnSecondary } from '../../components/ui'
import type { FlowState, SessionFlow } from './sessionFlow'

// Galat lokal alur: diblokir penjaga, offline, jaringan, atau tak terduga. Penolakan server tampil di spanduk halaman.
export function FlowFailure({ flow, state }: { flow: SessionFlow; state: FlowState }) {
  const f = state.failure
  if (state.phase !== 'failed' || f === null || f.kind === 'rejected') return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      <p className="break-words">{f.message}</p>
      {f.retryable ? (
        <>
          <p>
            Belum ada konfirmasi dari server, jadi perubahan ini mungkin sudah atau belum tersimpan. Mengirim ulang aman
            dan tidak menggandakan hasil.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={() => void flow.retry()}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={() => flow.dismiss()}>
              Hentikan percobaan
            </button>
          </div>
          <p className="text-xs">Setelah dihentikan, layar disegarkan dari server untuk melihat hasil sebenarnya.</p>
        </>
      ) : (
        <button type="button" className={btnSecondary} onClick={() => flow.dismiss()}>
          Tutup
        </button>
      )}
    </div>
  )
}
