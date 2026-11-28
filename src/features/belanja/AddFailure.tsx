import { btnSecondary } from '../../components/ui'
import { isSessionLevelCode, type AddState } from './sessionAdd'

// Galat penambahan di dekat formulir. Galat foto tampil di kolom foto; penolakan sesi-level di spanduk halaman.
export function AddFailure({
  state,
  online,
  onRetry,
  onDismiss,
}: {
  state: AddState
  online: boolean
  onRetry: () => void
  onDismiss: () => void
}) {
  const f = state.failure
  if (state.phase !== 'failed' || f === null || f.kind === 'photo') return null
  if (f.kind === 'rejected' && isSessionLevelCode(f.code)) return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      <p className="break-words">{f.message}</p>
      {f.retryable ? (
        <>
          <p>
            Belum ada konfirmasi dari server, jadi barang ini mungkin sudah atau belum ditambahkan. Mengirim ulang aman
            dan tidak menggandakan barang.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={onRetry} disabled={!online}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={onDismiss}>
              Hentikan percobaan
            </button>
          </div>
          <p className="text-xs">Setelah dihentikan, layar disegarkan dari server untuk melihat hasil sebenarnya.</p>
        </>
      ) : (
        <button type="button" className={btnSecondary} onClick={onDismiss}>
          Tutup
        </button>
      )}
    </div>
  )
}
