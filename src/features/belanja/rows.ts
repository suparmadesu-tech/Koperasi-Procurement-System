import { D } from '../../lib/money'
import type { ServerSession, ServerSessionItem, SessionItemRow, SessionRow } from './types'

const numStr = (v: number | string | null): string | null => (v === null ? null : new D(v).toString())

export function toSessionRow(r: ServerSession): SessionRow {
  return { ...r, total_estimate: numStr(r.total_estimate), total_actual: numStr(r.total_actual) }
}

export function toSessionItemRow(r: ServerSessionItem): SessionItemRow {
  return {
    ...r,
    price_snapshot: numStr(r.price_snapshot),
    price_actual: numStr(r.price_actual),
    quantity_needed: new D(r.quantity_needed).toString(),
    quantity_actual: numStr(r.quantity_actual),
  }
}
