import { useEffect, useState, useSyncExternalStore } from 'react'
import { catalogQuery, describeError } from './catalogStore'
import {
  acquireCatalogSync,
  getSyncState,
  requestCatalogRefresh,
  subscribeSyncState,
  type SyncState,
} from './catalogSync'
import type { CatalogData } from './types'

export function useCatalogSyncState(): SyncState {
  return useSyncExternalStore(subscribeSyncState, getSyncState, getSyncState)
}

// data bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useCatalog(workspaceId: string | null) {
  const [data, setData] = useState<CatalogData | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setData(null)
      return undefined
    }
    const sub = catalogQuery(workspaceId).subscribe({
      next: (value) => {
        setData(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireCatalogSync(workspaceId) : undefined), [workspaceId])

  const sync = useCatalogSyncState()
  return {
    data,
    loading: data === null && readError === null,
    readError,
    sync,
    refresh: requestCatalogRefresh,
  }
}
