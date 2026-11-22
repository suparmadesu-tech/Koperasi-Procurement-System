import { useCallback, useMemo, useRef, useState } from 'react'
import { createAttemptRunner } from './attemptRunner'
import { requestListRefresh } from './listSync'
import { submitListOp } from './submitListOp'
import type { ListOpResult, ListOpType } from './types'

export type OpOk = Extract<ListOpResult, { ok: true }>

// Satu operasi pada satu waktu per pemakai hook. Gagal retryable disimpan untuk dikirim ulang dengan op_id yang sama.
export function useListOp(workspaceId: string) {
  const runner = useMemo(
    () =>
      createAttemptRunner<ListOpType>(
        (type, payload, options) => submitListOp(workspaceId, type, payload, options),
        () => crypto.randomUUID(),
      ),
    [workspaceId],
  )
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)
  const after = useRef<((r: OpOk) => void) | null>(null)

  const finish = useCallback(
    (r: ListOpResult | null): ListOpResult | null => {
      setBusy(false)
      setPending(runner.hasPending())
      if (r === null) return r
      setError(r.ok ? null : r.message)
      // Ditolak server: ambil data terbaru supaya layar sama dengan server.
      if (!r.ok && !r.retryable && r.code !== 'OFFLINE' && r.code !== 'NO_CLIENT') requestListRefresh()
      return r
    },
    [runner],
  )

  const run = useCallback(
    async (type: ListOpType, payload: Record<string, unknown>, onOk: (r: OpOk) => void) => {
      after.current = onOk
      setBusy(true)
      setError(null)
      const r = finish(await runner.run(type, payload))
      if (r && r.ok) onOk(r)
      return r
    },
    [runner, finish],
  )

  const retry = useCallback(async () => {
    setBusy(true)
    setError(null)
    const r = finish(await runner.retry())
    if (r && r.ok) after.current?.(r)
    return r
  }, [runner, finish])

  const discard = useCallback(() => {
    runner.discard()
    setPending(false)
    setError(null)
    requestListRefresh()
  }, [runner])

  return { busy, error, pending, run, retry, discard }
}
