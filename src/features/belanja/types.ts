export type SessionStatus = 'active' | 'completed' | 'cancelled'
export type ItemStatus = 'to_buy' | 'in_cart' | 'purchased'
export const ITEM_STATUSES: readonly ItemStatus[] = ['to_buy', 'in_cart', 'purchased']

// Uang dan kuantitas disimpan lokal sebagai string desimal, bukan float (FR-038).
export interface SessionRow {
  id: string
  workspace_id: string
  status: SessionStatus
  started_by: string | null
  started_at: string
  ended_by: string | null
  ended_at: string | null
  // Dibekukan saat sesi dimulai (FR-024, FR-050).
  total_estimate: string | null
  unpriced_items_at_start: number | null
  // Dibekukan saat sesi selesai; kosong untuk sesi aktif dan batal.
  total_actual: string | null
  unpriced_items_purchased: number | null
  created_at: string
  updated_at: string
}

export interface ServerSession extends Omit<SessionRow, 'total_estimate' | 'total_actual'> {
  total_estimate: number | string | null
  total_actual: number | string | null
}

export interface SessionItemRow {
  id: string
  session_id: string
  workspace_id: string
  // Kosong untuk barang yang ditambahkan langsung ke sesi (FR-052).
  source_item_id: string | null
  product_id: string | null
  product_name_snapshot: string
  photo_path_snapshot: string | null
  unit_snapshot: string
  unit_id_snapshot: string | null
  allow_fraction_snapshot: boolean
  note_snapshot: string | null
  price_snapshot: string | null
  price_actual: string | null
  quantity_needed: string
  // Kosong tepat bila status to_buy.
  quantity_actual: string | null
  status: ItemStatus
  // Penghapusan oleh pengguna; hanya untuk barang yang ditambahkan langsung (FR-048).
  deleted_at: string | null
  created_at: string
  updated_at: string
}

export interface ServerSessionItem
  extends Omit<SessionItemRow, 'price_snapshot' | 'price_actual' | 'quantity_needed' | 'quantity_actual'> {
  price_snapshot: number | string | null
  price_actual: number | string | null
  quantity_needed: number | string
  quantity_actual: number | string | null
}

export interface SessionData {
  sessions: SessionRow[]
  items: SessionItemRow[]
}
