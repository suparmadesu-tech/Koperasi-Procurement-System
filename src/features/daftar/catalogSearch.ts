import type { CatalogData } from '../katalog/types'

export interface CatalogHit {
  id: string
  name: string
  unitName: string
  allowFraction: boolean
  price: string | null
}

export interface SearchResult {
  hits: CatalogHit[]
  total: number
  activeCount: number
}

function toHit(data: CatalogData, p: CatalogData['products'][number]): CatalogHit {
  const unit = data.units.find((u) => u.id === p.unit_id)
  return { id: p.id, name: p.name, unitName: unit?.name ?? '', allowFraction: unit?.allow_fraction ?? false, price: p.price }
}

// Hanya barang aktif yang dapat ditambahkan (FR-008). Pencarian dari data lokal (FR-007).
export function searchProducts(data: CatalogData, query: string, limit: number): SearchResult {
  const q = query.trim().toLowerCase()
  const active = data.products.filter((p) => !p.is_archived)
  const matched = (q === '' ? active : active.filter((p) => p.name.toLowerCase().includes(q))).sort(
    (a, b) => a.name.localeCompare(b.name, 'id') || a.id.localeCompare(b.id),
  )
  return { hits: matched.slice(0, limit).map((p) => toHit(data, p)), total: matched.length, activeCount: active.length }
}

export function findHit(data: CatalogData, id: string): CatalogHit | null {
  const p = data.products.find((x) => x.id === id && !x.is_archived)
  return p ? toHit(data, p) : null
}
