import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import { toSessionItemRow, toSessionRow } from './rows'
import type { ServerSession, ServerSessionItem, SessionData, SessionRow } from './types'

const sb = supabase as unknown as SupabaseClient

export const SESSION_COLUMNS =
  'id, workspace_id, status, started_by, started_at, ended_by, ended_at, total_estimate, unpriced_items_at_start, total_actual, unpriced_items_purchased, created_at, updated_at'
export const SESSION_ITEM_COLUMNS =
  'id, session_id, workspace_id, source_item_id, product_id, product_name_snapshot, photo_path_snapshot, unit_snapshot, unit_id_snapshot, allow_fraction_snapshot, note_snapshot, price_snapshot, price_actual, quantity_needed, quantity_actual, status, deleted_at, created_at, updated_at'

const PAGE_SIZE = 1000

// Yang disimpan lokal: sesi aktif dan sesi berakhir terbaru. Riwayat penuh dibaca langsung dari server (Tahap 5).
async function fetchSessions(workspaceId: string): Promise<ServerSession[]> {
  const active = await sb
    .from('shopping_sessions')
    .select(SESSION_COLUMNS)
    .eq('workspace_id', workspaceId)
    .eq('status', 'active')
  if (active.error) throw active.error
  const ended = await sb
    .from('shopping_sessions')
    .select(SESSION_COLUMNS)
    .eq('workspace_id', workspaceId)
    .in('status', ['completed', 'cancelled'])
    .order('ended_at', { ascending: false, nullsFirst: false })
    .limit(1)
  if (ended.error) throw ended.error
  return [
    ...((active.data ?? []) as unknown as ServerSession[]),
    ...((ended.data ?? []) as unknown as ServerSession[]),
  ]
}

// Termasuk baris yang dihapus pengguna: perhitungan menyaringnya lewat deleted_at (FR-048).
async function fetchItems(workspaceId: string, sessionIds: string[]): Promise<ServerSessionItem[]> {
  if (sessionIds.length === 0) return []
  const rows: ServerSessionItem[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from('shopping_session_items')
      .select(SESSION_ITEM_COLUMNS)
      .eq('workspace_id', workspaceId)
      .in('session_id', sessionIds)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as ServerSessionItem[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Baris lokal yang tidak ikut hasil server (sesi lama, barang yang tidak lagi diambil) dibuang.
export async function refreshSessions(workspaceId: string): Promise<void> {
  const sessions = (await fetchSessions(workspaceId)).map(toSessionRow)
  const items = (await fetchItems(workspaceId, sessions.map((s: SessionRow) => s.id))).map(toSessionItemRow)
  const keepSessions = new Set(sessions.map((s) => s.id))
  const keepItems = new Set(items.map((i) => i.id))
  const db = getDb()
  await db.transaction('rw', db.sessions, db.sessionItems, async () => {
    const localSessions = await db.sessions.where('workspace_id').equals(workspaceId).primaryKeys()
    const staleSessions = localSessions.filter((id) => !keepSessions.has(id))
    if (staleSessions.length > 0) await db.sessions.bulkDelete(staleSessions)
    await db.sessions.bulkPut(sessions)

    const localItems = await db.sessionItems.where('workspace_id').equals(workspaceId).primaryKeys()
    const staleItems = localItems.filter((id) => !keepItems.has(id))
    if (staleItems.length > 0) await db.sessionItems.bulkDelete(staleItems)
    await db.sessionItems.bulkPut(items)
  })
}

export const sessionQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<SessionData> => {
    const db = getDb()
    return {
      sessions: await db.sessions.where('workspace_id').equals(workspaceId).toArray(),
      items: await db.sessionItems.where('workspace_id').equals(workspaceId).toArray(),
    }
  })

export async function clearSessionLocal(): Promise<void> {
  const db = getDb()
  await db.transaction('rw', db.sessions, db.sessionItems, async () => {
    await Promise.all([db.sessions.clear(), db.sessionItems.clear()])
  })
}
