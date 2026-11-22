import { useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { describeError } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { selectSessionState, type SessionState } from './sessionSelectors'
import { sessionQuery } from './sessionStore'
import {
  acquireSessionSync,
  getSessionSyncState,
  requestSessionRefresh,
  subscribeSessionSyncState,
} from './sessionSync'
import type { SessionData } from './types'

export function useSessionSyncState(): SyncState {
  return useSyncExternalStore(subscribeSessionSyncState, getSessionSyncState, getSessionSyncState)
}

// data bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useSessionData(workspaceId: string | null) {
  const [data, setData] = useState<SessionData | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setData(null)
      return undefined
    }
    const sub = sessionQuery(workspaceId).subscribe({
      next: (value) => {
        setData(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireSessionSync(workspaceId) : undefined), [workspaceId])

  return { data, readError, sync: useSessionSyncState(), refresh: requestSessionRefresh }
}

export function useSessionState(workspaceId: string | null) {
  const { data, readError, sync, refresh } = useSessionData(workspaceId)
  const state: SessionState | null = useMemo(() => (data ? selectSessionState(data) : null), [data])
  return { state, loading: state === null && readError === null, readError, sync, refresh }
}
