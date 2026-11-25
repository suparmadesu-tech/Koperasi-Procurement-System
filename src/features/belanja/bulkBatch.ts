import { createAttemptRunner } from '../daftar/attemptRunner'
import type { ListOpResult } from '../daftar/types'
import type { SessionSubmit } from './itemOps'
import { setStatusPayload } from './sessionPayloads'
import type { SessionOpType } from './sessionRpc'

export interface BulkItem {
  id: string
  name: string
}

export type BulkOutcome = 'pending' | 'ok' | 'rejected'

export interface BulkEntry extends BulkItem {
  outcome: BulkOutcome
  code: string | null
  message: string | null
}

export type BulkPhase = 'idle' | 'confirm' | 'running' | 'halted' | 'done'
export type BulkHaltKind = 'network' | 'offline' | 'session' | 'unexpected'

export interface BulkHalt {
  kind: BulkHaltKind
  message: string
}

export interface BulkState {
  phase: BulkPhase
  entries: BulkEntry[]
  // Indeks barang yang sedang atau berikutnya diproses.
  cursor: number
  halt: BulkHalt | null
  // Ada pengiriman tanpa jawaban server: barang itu mungkin sudah tersimpan.
  uncertain: boolean
  discarded: boolean
}

export interface BulkReport {
  total: number
  ok: number
  rejected: Array<{ id: string; name: string; code: string; message: string }>
  unprocessed: number
  uncertain: boolean
  discarded: boolean
}

export interface BulkConfig {
  submit: SessionSubmit
  newId: () => string
  isOnline: () => boolean
  onDiscard?: () => void
}

const OFFLINE_MESSAGE = 'Anda sedang offline. Pemrosesan dihentikan sampai koneksi kembali.'
const UNEXPECTED_MESSAGE = 'Terjadi galat tak terduga. Pemrosesan dihentikan.'
const INITIAL: BulkState = { phase: 'idle', entries: [], cursor: 0, halt: null, uncertain: false, discarded: false }

export function buildBulkReport(s: Pick<BulkState, 'entries' | 'uncertain' | 'discarded'>): BulkReport {
  const rejected = s.entries
    .filter((e) => e.outcome === 'rejected')
    .map((e) => ({ id: e.id, name: e.name, code: e.code ?? 'KPS_REJECTED', message: e.message ?? 'Ditolak server.' }))
  return {
    total: s.entries.length,
    ok: s.entries.filter((e) => e.outcome === 'ok').length,
    rejected,
    unprocessed: s.entries.filter((e) => e.outcome === 'pending').length,
    uncertain: s.uncertain,
    discarded: s.discarded,
  }
}

// Laporan jujur: hanya yang dijawab server yang dihitung berhasil (SYNC-006).
export function bulkSummaryLine(r: BulkReport): string {
  const base = `${r.ok} berhasil di server, ${r.rejected.length} ditolak, ${r.unprocessed} belum diproses.`
  return r.uncertain
    ? `${base} Satu barang yang sedang dikirim belum ada konfirmasi dari server dan mungkin sudah tersimpan.`
    : base
}

export const bulkConfirmMessage = (count: number): string =>
  `${count} barang di keranjang akan ditandai sudah dibeli, satu per satu. Jumlah aktual dan harga tidak berubah. Setiap barang dikonfirmasi server; bila ada yang ditolak atau jaringan terputus, Anda akan melihat laporannya.`

// Aksi massal FR-034 dipecah klien menjadi satu session_set_status per barang, berurutan, op_id berbeda per barang.
// Penolakan server pada satu barang tidak menghentikan batch (SYNC-003); gagal jaringan menghentikannya
// dan menyisakan percobaan yang dikirim ulang dengan op_id yang sama (SYNC-004).
export function createBulkBatch(cfg: BulkConfig) {
  const runner = createAttemptRunner<SessionOpType>(cfg.submit, cfg.newId)
  let state: BulkState = INITIAL
  const listeners = new Set<() => void>()

  const set = (next: BulkState) => {
    state = next
    listeners.forEach((l) => l())
  }

  function halt(kind: BulkHaltKind, message: string) {
    set({ ...state, phase: 'halted', halt: { kind, message }, uncertain: runner.hasPending() })
  }

  function settle(index: number, outcome: BulkOutcome, code: string | null, message: string | null) {
    set({
      ...state,
      entries: state.entries.map((e, i) => (i === index ? { ...e, outcome, code, message } : e)),
      cursor: index + 1,
    })
  }

  // Fase 'running' dipasang sebelum await pertama, jadi konfirmasi ganda berikutnya diabaikan.
  async function drive(): Promise<void> {
    set({ ...state, phase: 'running', halt: null, uncertain: false })
    try {
      while (state.cursor < state.entries.length) {
        const index = state.cursor
        const entry = state.entries[index]
        if (!entry) break
        if (!cfg.isOnline()) {
          halt('offline', OFFLINE_MESSAGE)
          return
        }
        const r: ListOpResult | null = runner.hasPending()
          ? await runner.retry()
          : await runner.run('session_set_status', setStatusPayload(entry.id, 'purchased'))
        if (r === null) {
          halt('unexpected', UNEXPECTED_MESSAGE)
          return
        }
        if (r.ok) {
          settle(index, 'ok', null, null)
          continue
        }
        if (r.retryable) {
          halt('network', r.message)
          return
        }
        if (r.code === 'OFFLINE' || r.code === 'NO_CLIENT') {
          halt('offline', r.message)
          return
        }
        if (r.code === 'SESSION_EXPIRED') {
          halt('session', r.message)
          return
        }
        settle(index, 'rejected', r.code, r.message)
      }
      set({ ...state, phase: 'done', halt: null, uncertain: false })
    } catch {
      halt('unexpected', UNEXPECTED_MESSAGE)
    }
  }

  function open(items: BulkItem[]): void {
    if (state.phase !== 'idle' && state.phase !== 'done') return
    if (items.length === 0 || !cfg.isOnline()) return
    set({
      ...INITIAL,
      phase: 'confirm',
      entries: items.map((i) => ({ id: i.id, name: i.name, outcome: 'pending', code: null, message: null })),
    })
  }

  function cancel(): void {
    if (state.phase === 'confirm') set(INITIAL)
  }

  async function confirm(): Promise<void> {
    if (state.phase !== 'confirm') return
    await drive()
  }

  async function retry(): Promise<void> {
    if (state.phase !== 'halted') return
    // Offline: jangan memanggil pengirim, supaya op_id yang menunggu tidak terbuang.
    if (!cfg.isOnline()) return
    await drive()
  }

  // Menghentikan batch: sisa tidak diproses, dan layar disegarkan karena hasil pengiriman terakhir tidak diketahui.
  function discard(): void {
    if (state.phase !== 'halted') return
    if (runner.hasPending()) runner.discard()
    cfg.onDiscard?.()
    set({ ...state, phase: 'done', halt: null, discarded: true })
  }

  function close(): void {
    if (state.phase === 'done') set(INITIAL)
  }

  return {
    getState: (): BulkState => state,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    open,
    cancel,
    confirm,
    retry,
    discard,
    close,
  }
}

export type BulkBatch = ReturnType<typeof createBulkBatch>
