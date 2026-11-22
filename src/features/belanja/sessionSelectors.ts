import { isLiveItem } from './sessionMath'
import type { SessionData, SessionItemRow, SessionRow } from './types'

export interface SessionState {
  active: SessionRow | null
  activeItems: SessionItemRow[]
  // Sesi selesai atau batal terbaru, untuk ringkasan setelah sesi berakhir.
  lastEnded: SessionRow | null
  lastEndedItems: SessionItemRow[]
}

const time = (iso: string | null): number => {
  const t = iso === null ? NaN : Date.parse(iso)
  return Number.isNaN(t) ? 0 : t
}

export function selectSessionState(d: SessionData): SessionState {
  const active = d.sessions.find((s) => s.status === 'active') ?? null
  const lastEnded =
    d.sessions
      .filter((s) => s.status !== 'active')
      .sort((a, b) => time(b.ended_at ?? b.created_at) - time(a.ended_at ?? a.created_at))[0] ?? null

  const itemsOf = (s: SessionRow | null): SessionItemRow[] =>
    s === null
      ? []
      : d.items
          .filter((i) => i.session_id === s.id && isLiveItem(i))
          .sort((a, b) => a.product_name_snapshot.localeCompare(b.product_name_snapshot, 'id') || a.id.localeCompare(b.id))

  return { active, activeItems: itemsOf(active), lastEnded, lastEndedItems: itemsOf(lastEnded) }
}
