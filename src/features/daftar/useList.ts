import { useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { describeError } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { useCatalog } from '../katalog/useCatalog'
import { listQuery } from './listStore'
import { acquireListSync, getListSyncState, requestListRefresh, subscribeListSyncState } from './listSync'
import { buildListView, type ListView } from './listView'
import type { ListItemRow } from './types'

export function useListSyncState(): SyncState {
  return useSyncExternalStore(subscribeListSyncState, getListSyncState, getListSyncState)
}

// items bernilai null selama pembacaan pertama dari Dexie belum selesai.
export function useListItems(workspaceId: string | null) {
  const [items, setItems] = useState<ListItemRow[] | null>(null)
  const [readError, setReadError] = useState<string | null>(null)

  useEffect(() => {
    if (!workspaceId) {
      setItems(null)
      return undefined
    }
    const sub = listQuery(workspaceId).subscribe({
      next: (value) => {
        setItems(value)
        setReadError(null)
      },
      error: (e) => setReadError(describeError(e)),
    })
    return () => sub.unsubscribe()
  }, [workspaceId])

  useEffect(() => (workspaceId ? acquireListSync(workspaceId) : undefined), [workspaceId])

  return { items, readError, sync: useListSyncState(), refresh: requestListRefresh }
}

// Daftar digabung dengan katalog lokal untuk nama, satuan, foto, dan harga.
export function useDaftar(workspaceId: string | null) {
  const catalog = useCatalog(workspaceId)
  const list = useListItems(workspaceId)

  const view: ListView | null = useMemo(
    () => (list.items && catalog.data ? buildListView(list.items, catalog.data) : null),
    [list.items, catalog.data],
  )
  const readError = list.readError ?? catalog.readError

  return {
    view,
    loading: view === null && readError === null,
    readError,
    sync: list.sync,
    catalogSync: catalog.sync,
    refresh: () => {
      list.refresh()
      catalog.refresh()
    },
  }
}
