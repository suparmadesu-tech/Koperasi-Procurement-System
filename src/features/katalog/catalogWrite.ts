import type { SupabaseClient } from '@supabase/supabase-js'
import { getDb } from '../../lib/db'
import { supabase } from '../../lib/supabase'
import {
  CATEGORY_COLUMNS,
  PRODUCT_COLUMNS,
  UNIT_COLUMNS,
  isOnline,
} from './catalogStore'
import { mapWriteError } from './errors'
import { priceToWire, productPatchToColumns, toProductRow, type ProductPatch, type ServerProduct } from './rows'
import type { CatalogError, CategoryRow, ProductRow, Result, UnitRow } from './types'

const sb = supabase as unknown as SupabaseClient

interface Spec<R> {
  table: string
  columns: string
  adapt: (raw: unknown) => R
  store: (row: R) => Promise<unknown>
}

const categorySpec: Spec<CategoryRow> = {
  table: 'categories',
  columns: CATEGORY_COLUMNS,
  adapt: (r) => r as CategoryRow,
  store: (r) => getDb().categories.put(r),
}
const unitSpec: Spec<UnitRow> = {
  table: 'units',
  columns: UNIT_COLUMNS,
  adapt: (r) => r as UnitRow,
  store: (r) => getDb().units.put(r),
}
const productSpec: Spec<ProductRow> = {
  table: 'products',
  columns: PRODUCT_COLUMNS,
  adapt: (r) => toProductRow(r as ServerProduct),
  store: (r) => getDb().products.put(r),
}

const fail = <T>(error: CatalogError): Result<T> => ({ ok: false, error })
const OFFLINE: CatalogError = {
  code: 'OFFLINE',
  message: 'Mengubah katalog memerlukan koneksi internet. Sambungkan perangkat, lalu coba lagi.',
}
// 0 baris berubah berarti RLS menolak tanpa galat (Bagian 3, bagian 8).
const NO_ROWS: CatalogError = {
  code: 'ROWS_NOT_AFFECTED',
  message: 'Perubahan ditolak server. Anda mungkin tidak berhak mengubah data ini, atau datanya sudah tidak ada.',
}

// Cache lokal hanya cermin; bila gagal ditulis, Realtime dan penyegaran berikutnya memperbaikinya.
async function mirror<R>(spec: Spec<R>, row: R) {
  try {
    await spec.store(row)
  } catch {
    /* sengaja diabaikan */
  }
}

async function insertOne<R>(spec: Spec<R>, row: Record<string, unknown>): Promise<Result<R>> {
  if (!isOnline()) return fail(OFFLINE)
  try {
    const { data, error } = await sb.from(spec.table).insert(row).select(spec.columns).single()
    if (error) return fail(mapWriteError(error))
    const saved = spec.adapt(data)
    await mirror(spec, saved)
    return { ok: true, data: saved }
  } catch (e) {
    return fail(mapWriteError(e as { message?: string }))
  }
}

async function updateOne<R>(
  spec: Spec<R>,
  workspaceId: string,
  id: string,
  patch: Record<string, unknown>,
): Promise<Result<R>> {
  if (Object.keys(patch).length === 0) {
    return fail({ code: 'KPS_INVALID_INPUT', message: 'Tidak ada perubahan untuk disimpan.' })
  }
  if (!isOnline()) return fail(OFFLINE)
  try {
    const { data, error } = await sb
      .from(spec.table)
      .update(patch)
      .eq('id', id)
      .eq('workspace_id', workspaceId)
      .select(spec.columns)
    if (error) return fail(mapWriteError(error))
    const rows = (data ?? []) as unknown[]
    if (rows.length === 0) return fail(NO_ROWS)
    const saved = spec.adapt(rows[0])
    await mirror(spec, saved)
    return { ok: true, data: saved }
  } catch (e) {
    return fail(mapWriteError(e as { message?: string }))
  }
}

export const createCategory = (workspaceId: string, v: { name: string }) =>
  insertOne(categorySpec, { workspace_id: workspaceId, name: v.name })

export const updateCategory = (
  workspaceId: string,
  id: string,
  patch: { name?: string; is_archived?: boolean },
) => updateOne(categorySpec, workspaceId, id, { ...patch })

export const createUnit = (workspaceId: string, v: { name: string; allow_fraction: boolean }) =>
  insertOne(unitSpec, { workspace_id: workspaceId, name: v.name, allow_fraction: v.allow_fraction })

export const updateUnit = (
  workspaceId: string,
  id: string,
  patch: { name?: string; allow_fraction?: boolean; is_archived?: boolean },
) => updateOne(unitSpec, workspaceId, id, { ...patch })

export const createProduct = (
  workspaceId: string,
  v: { name: string; categoryId: string; unitId: string; price: string | null },
) =>
  insertOne(productSpec, {
    workspace_id: workspaceId,
    name: v.name,
    category_id: v.categoryId,
    unit_id: v.unitId,
    price: priceToWire(v.price),
  })

export const updateProduct = (workspaceId: string, id: string, patch: ProductPatch) =>
  updateOne(productSpec, workspaceId, id, productPatchToColumns(patch))
