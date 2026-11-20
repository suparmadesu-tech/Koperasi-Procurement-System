import { btnSecondary } from '../../components/ui'

export function OpNotice({
  error,
  pending,
  busy,
  onRetry,
  onDiscard,
}: {
  error: string | null
  pending: boolean
  busy: boolean
  onRetry: () => void
  onDiscard: () => void
}) {
  if (!error && !pending) return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      {error ? <p className="break-words">{error}</p> : null}
      {pending ? (
        <>
          <p>Perubahan ini mungkin sudah tersimpan di server. Mengirim ulang aman dan tidak menggandakan barang.</p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={onRetry} disabled={busy}>
              {busy ? 'Mengirim...' : 'Coba lagi'}
            </button>
            <button type="button" className={btnSecondary} onClick={onDiscard} disabled={busy}>
              Batalkan
            </button>
          </div>
        </>
      ) : null}
    </div>
  )
}
