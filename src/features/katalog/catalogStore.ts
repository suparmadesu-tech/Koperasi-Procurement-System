import { liveQuery } from 'dexie'
import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import { toProductRow, type ServerProduct } from './rows'
import type { CatalogData, CategoryRow, UnitRow } from './types'

const sb = supabase as unknown as SupabaseClient

export const CATEGORY_COLUMNS = 'id, workspace_id, name, is_archived, updated_at'
export const UNIT_COLUMNS = 'id, workspace_id, name, allow_fraction, is_archived, updated_at'
export const PRODUCT_COLUMNS =
  'id, workspace_id, category_id, unit_id, name, photo_path, price, is_archived, updated_at'

// Batas baris per permintaan di Supabase adalah 1000 secara bawaan.
const PAGE_SIZE = 1000

export const isOnline = () => typeof navigator === 'undefined' || navigator.onLine

export function describeError(e: unknown): string {
  if (e instanceof Error) return e.message
  if (e && typeof e === 'object' && 'message' in e) return String((e as { message: unknown }).message)
  return String(e)
}

async function fetchAll<T>(table: string, columns: string, workspaceId: string): Promise<T[]> {
  const rows: T[] = []
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await sb
      .from(table)
      .select(columns)
      .eq('workspace_id', workspaceId)
      .order('id')
      .range(from, from + PAGE_SIZE - 1)
    if (error) throw error
    const page = (data ?? []) as unknown as T[]
    rows.push(...page)
    if (page.length < PAGE_SIZE) return rows
  }
}

// Server tidak pernah menghapus baris katalog, jadi cukup bulkPut tanpa menghapus yang lokal.
export async function refreshCatalog(workspaceId: string): Promise<void> {
  const [categories, units, rawProducts] = await Promise.all([
    fetchAll<CategoryRow>('categories', CATEGORY_COLUMNS, workspaceId),
    fetchAll<UnitRow>('units', UNIT_COLUMNS, workspaceId),
    fetchAll<ServerProduct>('products', PRODUCT_COLUMNS, workspaceId),
  ])
  const products = rawProducts.map(toProductRow)
  const db = getDb()
  await db.transaction('rw', db.categories, db.units, db.products, async () => {
    await db.categories.bulkPut(categories)
    await db.units.bulkPut(units)
    await db.products.bulkPut(products)
  })
}

export const catalogQuery = (workspaceId: string) =>
  liveQuery(async (): Promise<CatalogData> => {
    const db = getDb()
    return {
      categories: await db.categories.where('workspace_id').equals(workspaceId).toArray(),
      units: await db.units.where('workspace_id').equals(workspaceId).toArray(),
      products: await db.products.where('workspace_id').equals(workspaceId).toArray(),
    }
  })

// Dipakai saat keluar (FR-002). Tabel ops sengaja tidak disentuh di sini.
export async function clearCatalogLocal(): Promise<void> {
  const db = getDb()
  await db.transaction('rw', db.categories, db.units, db.products, async () => {
    await Promise.all([db.categories.clear(), db.units.clear(), db.products.clear()])
  })
}
