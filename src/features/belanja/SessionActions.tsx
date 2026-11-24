import { useMemo } from 'react'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { useOnline } from '../daftar/useOnline'
import { FlowFailure } from './FlowFailure'
import { CANCEL_DIALOG_MESSAGE, endDialogMessage } from './flowText'
import type { FlowState } from './sessionFlow'
import { returnPreview } from './sessionMath'
import type { SessionItemRow } from './types'
import { useSessionFlow } from './useSessionFlow'

const holds = (s: FlowState) => s.phase === 'checking' || s.phase === 'sending' || s.phase === 'done'
const awaitsRetry = (s: FlowState) => s.phase === 'failed' && s.failure !== null && s.failure.retryable

export function SessionActions({
  workspaceId,
  sessionId,
  items,
}: {
  workspaceId: string
  sessionId: string
  items: SessionItemRow[]
}) {
  const online = useOnline()
  const end = useSessionFlow(workspaceId, 'end', sessionId)
  const cancel = useSessionFlow(workspaceId, 'cancel', sessionId)
  const returning = useMemo(() => returnPreview(items).count, [items])

  const locked = holds(end.state) || holds(cancel.state) || awaitsRetry(end.state) || awaitsRetry(cancel.state)
  const endLabel =
    end.state.phase === 'checking' ? 'Memeriksa...' : end.state.phase === 'sending' ? 'Mengakhiri...' : 'Akhiri sesi'
  const cancelLabel = cancel.state.phase === 'sending' ? 'Membatalkan...' : 'Batalkan sesi'

  return (
    <section aria-labelledby="kelola-sesi" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="kelola-sesi" className="font-semibold">
        Kelola sesi
      </h2>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className={btnPrimary}
          onClick={() => void end.begin()}
          disabled={locked || !online}
        >
          {endLabel}
        </button>
        <button
          type="button"
          className={btnSecondary}
          onClick={() => void cancel.begin()}
          disabled={locked || !online}
        >
          {cancelLabel}
        </button>
      </div>
      {!online ? (
        <p className="text-sm">Anda sedang offline. Mengakhiri atau membatalkan sesi memerlukan koneksi internet.</p>
      ) : null}
      <FlowFailure flow={end.flow} state={end.state} />
      <FlowFailure flow={cancel.flow} state={cancel.state} />

      <ConfirmDialog
        open={end.state.phase === 'confirm'}
        title="Akhiri sesi belanja?"
        message={endDialogMessage(returning, end.state.note)}
        confirmLabel="Akhiri sesi"
        cancelLabel="Kembali"
        onConfirm={() => void end.flow.confirm()}
        onCancel={() => end.flow.dismiss()}
      />
      <ConfirmDialog
        open={end.state.phase === 'confirm_warning'}
        title="Ada perubahan yang belum tersimpan"
        message={end.state.warning ?? ''}
        confirmLabel="Tetap akhiri sesi"
        cancelLabel="Kembali"
        onConfirm={() => void end.flow.confirm()}
        onCancel={() => end.flow.dismiss()}
      />
      <ConfirmDialog
        open={cancel.state.phase === 'confirm'}
        title="Batalkan sesi belanja?"
        message={CANCEL_DIALOG_MESSAGE}
        confirmLabel="Ya, batalkan sesi"
        cancelLabel="Kembali ke sesi"
        onConfirm={() => void cancel.flow.confirm()}
        onCancel={() => cancel.flow.dismiss()}
      />
    </section>
  )
}
