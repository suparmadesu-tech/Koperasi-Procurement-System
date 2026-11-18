export interface CategoryRow {
  id: string
  workspace_id: string
  name: string
  is_archived: boolean
  updated_at: string
}

export interface UnitRow extends CategoryRow {
  allow_fraction: boolean
}

export interface ProductRow {
  id: string
  workspace_id: string
  category_id: string
  unit_id: string
  name: string
  photo_path: string | null
  // Rupiah bulat sebagai string desimal; tidak pernah float (FR-038).
  price: string | null
  is_archived: boolean
  updated_at: string
}

export interface CatalogData {
  categories: CategoryRow[]
  units: UnitRow[]
  products: ProductRow[]
}

export interface CatalogError {
  code: string
  message: string
}

export type Result<T> = { ok: true; data: T } | { ok: false; error: CatalogError }

// Batas BR-039. Satuan katalog 50 karena disalin ke unit_snapshot.
export const TEXT_LIMITS = { categoryName: 200, unitName: 50, productName: 200 } as const
