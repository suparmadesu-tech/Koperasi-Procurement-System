import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { describeError, isOnline } from '../katalog/catalogStore'
import type { SyncState } from '../katalog/catalogSync'

const sb = supabase as unknown as SupabaseClient

export interface SyncControllerConfig {
  channelPrefix: string
  tables: readonly string[]
  refresh: (workspaceId: string) => Promise<void>
  debounceMs?: number
}

// Refetch penuh berjeda, sama seperti katalog dan daftar. Satu langganan Realtime dipakai bersama.
export function createSyncController(cfg: SyncControllerConfig) {
  const debounce = cfg.debounceMs ?? 1500
  let state: SyncState = { status: 'idle', lastSyncedAt: null, error: null }
  const listeners = new Set<() => void>()
  let activeWorkspace: string | null = null
  let holders = 0
  let channel: RealtimeChannel | null = null
  let timer: ReturnType<typeof setTimeout> | undefined
  let running = false
  let rerun = false

  const setState = (patch: Partial<SyncState>) => {
    state = { ...state, ...patch }
    listeners.forEach((l) => l())
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
      await cfg.refresh(workspaceId)
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

  function schedule(delay: number = debounce) {
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
    let ch = sb.channel(`${cfg.channelPrefix}-${workspaceId}`)
    for (const table of cfg.tables) {
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

  return {
    getState: (): SyncState => state,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    acquire: (workspaceId: string): (() => void) => {
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
    },
    requestRefresh: () => schedule(0),
  }
}
