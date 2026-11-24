import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary } from '../../components/ui'
import { useOnline } from '../daftar/useOnline'
import { FlowFailure } from './FlowFailure'
import { startDialogMessage, type StartFacts } from './flowText'
import { useSessionFlow } from './useSessionFlow'

export function StartSession({
  workspaceId,
  summary,
  catalogPending,
}: {
  workspaceId: string
  summary: StartFacts | null
  catalogPending: boolean
}) {
  const online = useOnline()
  const { flow, state, begin } = useSessionFlow(workspaceId, 'start', null)
  const phase = state.phase
  const holding = phase === 'checking' || phase === 'sending' || phase === 'done'
  const awaitingRetry = phase === 'failed' && state.failure !== null && state.failure.retryable
  const reason = !online
    ? 'Anda sedang offline. Memulai sesi memerlukan koneksi internet.'
    : summary === null
      ? 'Menunggu daftar kebutuhan selesai dibaca dari perangkat.'
      : null
  const label = phase === 'checking' ? 'Memeriksa...' : phase === 'sending' ? 'Memulai...' : 'Mulai sesi belanja'

  return (
    <div className="space-y-3">
      <button
        type="button"
        className={btnPrimary}
        onClick={() => void begin()}
        disabled={reason !== null || holding || awaitingRetry}
      >
        {label}
      </button>
      {reason ? <p className="text-sm">{reason}</p> : null}
      <FlowFailure flow={flow} state={state} />
      <ConfirmDialog
        open={phase === 'confirm'}
        title="Mulai sesi belanja?"
        message={summary ? startDialogMessage(summary, catalogPending, state.note) : ''}
        confirmLabel="Mulai sesi"
        cancelLabel="Kembali"
        onConfirm={() => void flow.confirm()}
        onCancel={() => flow.dismiss()}
      />
    </div>
  )
}
