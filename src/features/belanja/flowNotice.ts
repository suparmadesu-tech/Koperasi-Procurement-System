import type { FlowAction } from './sessionFlow'

export interface FlowNotice {
  tone: 'info' | 'error'
  text: string
}

export type FlowOutcome = { ok: true; data: Record<string, unknown> } | { ok: false; message: string }

function count(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v
  return Array.isArray(v) ? v.length : null
}

// Pesan sukses hanya setelah jawaban server diterima (SYNC-006).
export function flowNoticeFor(action: FlowAction, outcome: FlowOutcome): FlowNotice {
  if (!outcome.ok) return { tone: 'error', text: outcome.message }
  if (action === 'start') {
    const n = count(outcome.data.item_count)
    return {
      tone: 'info',
      text: n === null ? 'Sesi belanja dimulai di server.' : `Sesi belanja dimulai di server dengan ${n} barang.`,
    }
  }
  if (action === 'end') {
    const n = count(outcome.data.returned_items)
    return {
      tone: 'info',
      text:
        n === null
          ? 'Sesi belanja diakhiri di server.'
          : `Sesi belanja diakhiri di server. ${n} barang dikembalikan ke daftar kebutuhan.`,
    }
  }
  return {
    tone: 'info',
    text: 'Sesi belanja dibatalkan di server. Semua barang dikembalikan ke daftar kebutuhan.',
  }
}

// Disimpan di luar komponen supaya pesan bertahan saat layar berpindah antara sesi aktif dan tanpa sesi.
let current: FlowNotice | null = null
const listeners = new Set<() => void>()

export const getFlowNotice = (): FlowNotice | null => current

export function setFlowNotice(next: FlowNotice | null): void {
  current = next
  listeners.forEach((l) => l())
}

export const clearFlowNotice = (): void => setFlowNotice(null)

export function subscribeFlowNotice(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
