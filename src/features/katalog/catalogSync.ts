import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { describeError, isOnline, refreshCatalog } from './catalogStore'

const sb = supabase as unknown as SupabaseClient

export type SyncStatus = 'idle' | 'syncing' | 'ok' | 'offline' | 'error'
export interface SyncState {
  status: SyncStatus
  lastSyncedAt: string | null
  error: string | null
}

const TABLES = ['categories', 'units', 'products'] as const
// Impor besar memicu banyak event; digabung jadi satu penyegaran.
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

export const getSyncState = (): SyncState => state

export function subscribeSyncState(listener: () => void): () => void {
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
    await refreshCatalog(workspaceId)
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
  let ch = sb.channel(`kps-catalog-${workspaceId}`)
  for (const table of TABLES) {
    ch = ch.on(
      'postgres_changes',
      { event: '*', schema: 'public', table, filter: `workspace_id=eq.${workspaceId}` },
      () => schedule(),
    )
  }
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

// Satu langganan Realtime dipakai bersama; komponen yang memanggilnya menghitung referensi.
export function acquireCatalogSync(workspaceId: string): () => void {
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

export const requestCatalogRefresh = () => schedule(0)
