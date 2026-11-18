import type { ProductRow } from './types'

export type ArchiveFilter = 'active' | 'archived' | 'all'

export interface CatalogFilter {
  query?: string
  categoryId?: string | null
  archive?: ArchiveFilter
}

export function normalizeText(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim()
}

const collator = new Intl.Collator('id', { sensitivity: 'base', numeric: true })

export const compareByName = (a: { name: string; id: string }, b: { name: string; id: string }) =>
  collator.compare(a.name, b.name) || a.id.localeCompare(b.id)

// Semua kata pada query harus ada di nama (FR-007). Hasil diurutkan menurut nama.
export function filterProducts(products: readonly ProductRow[], filter: CatalogFilter = {}): ProductRow[] {
  const tokens = normalizeText(filter.query ?? '').split(' ').filter(Boolean)
  const archive = filter.archive ?? 'all'
  const out = products.filter((p) => {
    if (archive === 'active' && p.is_archived) return false
    if (archive === 'archived' && !p.is_archived) return false
    if (filter.categoryId && p.category_id !== filter.categoryId) return false
    if (tokens.length === 0) return true
    const name = normalizeText(p.name)
    return tokens.every((t) => name.includes(t))
  })
  return out.sort(compareByName)
}

// Pilihan untuk form: hanya yang aktif, ditambah nilai yang sedang dipakai walau diarsipkan (FR-047).
export function selectableOptions<T extends { id: string; name: string; is_archived: boolean }>(
  rows: readonly T[],
  currentId?: string | null,
): T[] {
  return rows.filter((r) => !r.is_archived || r.id === currentId).sort(compareByName)
}

export function indexById<T extends { id: string }>(rows: readonly T[]): Map<string, T> {
  return new Map(rows.map((r) => [r.id, r]))
}
