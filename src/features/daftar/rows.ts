import { D } from '../../lib/money'
import type { ListItemRow, ServerListItem } from './types'

// PostgREST mengirim numeric sebagai angka JSON; disimpan lokal sebagai string.
export function toListItemRow(r: ServerListItem): ListItemRow {
  return { ...r, quantity_needed: new D(r.quantity_needed).toString() }
}

// Kuantitas maksimal 3 desimal dan di bawah 1 miliar, aman sebagai Number.
export const quantityToWire = (q: string): number => Number(q)
