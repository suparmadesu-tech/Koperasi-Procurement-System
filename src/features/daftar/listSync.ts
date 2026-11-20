import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { describeError, isOnline } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'
import { refreshList } from './listStore'

const sb = supabase as unknown as SupabaseClient

// Mulai atau batal sesi juga mengubah baris ini, jadi satu tabel cukup.
const TABLE = 'shopping_list_items'
const DEBOUNCE_MS = 1500

let state: SyncState = { status: 'idle', lastSyncedAt: null, error: null }
const listeners = new Set<() => void>()
let activeWorkspace: string | null = null
let holders = 0
let channel: RealtimeChannel | null = null
let timer: ReturnType<typeof setTimeout> | undefined
let running = false
let rerun = false

function setState(patch: Partial<SyncState>) {
  state = { ...state, ...patch }
  listeners.forEach((l) => l())
}

export const getListSyncState = (): SyncState => state

export function subscribeListSyncState(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

async function run() {
  const workspaceId = activeWorkspace
  if (!workspaceId) return
  if (running) {
    rerun = true
    return
  }
  if (!isOnline()) {
    setState({ status: 'offline' })
    return
  }
  running = true
  setState({ status: 'syncing', error: null })
  try {
    await refreshList(workspaceId)
    setState({ status: 'ok', lastSyncedAt: new Date().toISOString() })
  } catch (e) {
    setState({ status: isOnline() ? 'error' : 'offline', error: describeError(e) })
  } finally {
    running = false
    if (rerun) {
      rerun = false
      schedule(0)
    }
  }
}

function schedule(delay: number = DEBOUNCE_MS) {
  clearTimeout(timer)
  timer = setTimeout(() => {
    void run()
  }, delay)
}

const onOnline = () => schedule(0)
const onVisible = () => {
  if (document.visibilityState === 'visible') schedule(0)
}

function start(workspaceId: string) {
  activeWorkspace = workspaceId
  const ch = sb
    .channel(`kps-list-${workspaceId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: TABLE, filter: `workspace_id=eq.${workspaceId}` },
      () => schedule(),
    )
  // Setelah tersambung ulang, ambil ulang agar event yang terlewat tidak hilang.
  channel = ch.subscribe((status) => {
    if (status === 'SUBSCRIBED') schedule(0)
  })
  window.addEventListener('online', onOnline)
  document.addEventListener('visibilitychange', onVisible)
  schedule(0)
}

function stop() {
  clearTimeout(timer)
  window.removeEventListener('online', onOnline)
  document.removeEventListener('visibilitychange', onVisible)
  if (channel) void sb.removeChannel(channel)
  channel = null
  activeWorkspace = null
  setState({ status: 'idle' })
}

export function acquireListSync(workspaceId: string): () => void {
  if (activeWorkspace !== null && activeWorkspace !== workspaceId) {
    stop()
    holders = 0
  }
  if (activeWorkspace === null) start(workspaceId)
  holders += 1
  let released = false
  return () => {
    if (released || activeWorkspace !== workspaceId) return
    released = true
    holders -= 1
    if (holders <= 0) stop()
  }
}

export const requestListRefresh = () => schedule(0)
