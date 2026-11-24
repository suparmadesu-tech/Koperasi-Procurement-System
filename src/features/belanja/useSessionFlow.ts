import { useMemo, useSyncExternalStore } from 'react'
import { useCallback } from 'react'
import { isOnline } from '../katalog/catalogStore'
import { clearFlowNotice, flowNoticeFor, setFlowNotice } from './flowNotice'
import { createSessionFlow, endGuard, noGuard, startGuard, type FlowAction } from './sessionFlow'
import { checkEndLive, checkStartLive } from './sessionGuardsLive'
import { cancelSessionPayload, endSessionPayload, startSessionPayload } from './sessionPayloads'
import type { SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

const OP: Record<FlowAction, SessionOpType> = {
  start: 'kps_start_session',
  end: 'kps_end_session',
  cancel: 'kps_cancel_session',
}

function requireId(id: string | null): string {
  if (id === null) throw new Error('sessionId diperlukan')
  return id
}

// Menghubungkan pengendali alur murni dengan pengirim sesi yang sudah ada. Tidak ada pola kirim baru.
export function useSessionFlow(workspaceId: string, action: FlowAction, sessionId: string | null) {
  const flow = useMemo(
    () =>
      createSessionFlow({
        opType: OP[action],
        payload: () =>
          action === 'start'
            ? startSessionPayload()
            : action === 'end'
              ? endSessionPayload(requireId(sessionId))
              : cancelSessionPayload(requireId(sessionId)),
        guard: action === 'start' ? startGuard(checkStartLive) : action === 'end' ? endGuard(checkEndLive) : noGuard,
        recheckBeforeSend: action === 'start',
        submit: (type, payload, options) => submitSessionOp(workspaceId, type, payload, options),
        isOnline,
        newId: () => crypto.randomUUID(),
        // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
        onDiscard: requestSessionRefresh,
        // Hanya hasil yang dinilai server yang dibawa ke spanduk halaman, karena layar dapat berpindah.
        onSettled: (o) => {
          if (o.ok) setFlowNotice(flowNoticeFor(action, { ok: true, data: o.data }))
          else if (o.failure.kind === 'rejected') {
            setFlowNotice(flowNoticeFor(action, { ok: false, message: o.failure.message }))
          }
        },
      }),
    [workspaceId, action, sessionId],
  )
  const state = useSyncExternalStore(flow.subscribe, flow.getState, flow.getState)
  const begin = useCallback(() => {
    clearFlowNotice()
    return flow.begin()
  }, [flow])
  return { flow, state, begin }
}
