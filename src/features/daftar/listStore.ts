import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import { toListItemRow } from './rows'
import type { ListItemRow, ServerListItem } from './types'

const sb = supabase as unknown as SupabaseClient

export const LIST_ITEM_COLUMNS =
  'id, workspace_id, shopping_list_id, product_id, manual_name, manual_unit, photo_path, note, quantity_needed, created_at, updated_at'

const PAGE_SIZE = 1000

async function fetchActive(workspaceId: string): Promise<ServerListItem[]> {
  const rows: ServerListItem[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from('shopping_list_items')
      .select(LIST_ITEM_COLUMNS)
      .eq('workspace_id', workspaceId)
      .is('deleted_at', null)
      .is('moved_session_id', null)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as ServerListItem[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Barang yang dihapus atau dipindahkan hilang dari hasil server, jadi baris lokal yang tidak ikut harus dibuang.
export async function refreshList(workspaceId: string): Promise<void> {
  const rows = (await fetchActive(workspaceId)).map(toListItemRow)
  const keep = new Set(rows.map((r) => r.id))
  const db = getDb()
  await db.transaction('rw', db.listItems, async () => {
    const local = await db.listItems.where('workspace_id').equals(workspaceId).primaryKeys()
    const stale = local.filter((id) => !keep.has(id))
    if (stale.length > 0) await db.listItems.bulkDelete(stale)
    await db.listItems.bulkPut(rows)
  })
}

export const listQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<ListItemRow[]> => {
    return getDb().listItems.where('workspace_id').equals(workspaceId).toArray()
  })

export async function clearListLocal(): Promise<void> {
  await getDb().listItems.clear()
}
