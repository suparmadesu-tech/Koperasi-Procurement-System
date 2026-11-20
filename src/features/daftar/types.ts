// Barang daftar aktif: belum dihapus dan belum dipindahkan ke sesi.
export interface ListItemRow {
  id: string
  workspace_id: string
  shopping_list_id: string
  product_id: string | null
  manual_name: string | null
  manual_unit: string | null
  photo_path: string | null
  note: string | null
  // numeric dari server disimpan lokal sebagai string desimal, bukan float (FR-038).
  quantity_needed: string
  created_at: string
  updated_at: string
}

export interface ServerListItem extends Omit<ListItemRow, 'quantity_needed'> {
  quantity_needed: number | string
}

// Batas BR-039. Satuan manual 50 karena disalin ke unit_snapshot.
export const LIST_TEXT_LIMITS = { itemName: 200, manualUnit: 50, note: 1000 } as const

export type ListOpType =
  | 'add_catalog_to_list'
  | 'list_add_manual'
  | 'list_set_quantity'
  | 'list_delete'
  | 'list_set_photo'

// retryable true: operasi mungkin sudah sampai ke server, kirim ulang dengan opId yang sama.
export type ListOpResult =
  | { ok: true; opId: string; data: Record<string, unknown>; replayed: boolean }
  | { ok: false; opId: string; code: string; message: string; retryable: boolean }
