import { createAttemptRunner } from '../daftar/attemptRunner'
import type { SubmitOptions } from '../daftar/submitCore'
import type { ListOpResult } from '../daftar/types'
import type { SessionOpType } from './sessionRpc'

export type SessionSubmit = (
  type: SessionOpType,
  payload: Record<string, unknown>,
  options: SubmitOptions,
) => Promise<ListOpResult>

export type ItemOpType = 'session_set_status' | 'session_set_quantity_actual' | 'session_set_price_actual'
export type ItemFailureKind = 'network' | 'offline' | 'rejected' | 'unexpected'

export interface ItemFailure {
  kind: ItemFailureKind
  code: string
  message: string
  // true: percobaan menunggu kirim ulang dengan op_id sama, atau dihentikan pengguna.
  retryable: boolean
}

export interface ItemOpState {
  phase: 'idle' | 'sending' | 'failed'
  failure: ItemFailure | null
}

// Hasil terakhir yang sudah dikonfirmasi server; dibaca pembaca layar lewat satu region status.
export interface LastOk {
  seq: number
  text: string
}

export type RunOutcome = { status: 'ignored' } | { status: 'ok' } | { status: 'failed'; failure: ItemFailure }

export interface ItemOpsConfig {
  submit: SessionSubmit
  newId: () => string
  isOnline: () => boolean
  onDiscard?: () => void
}

interface AttemptRunner {
  run: (type: SessionOpType, payload: Record<string, unknown>) => Promise<ListOpResult>
  retry: () => Promise<ListOpResult | null>
  discard: () => void
  hasPending: () => boolean
}

interface Slot {
  runner: AttemptRunner
  state: ItemOpState
  okText: string
}

const IDLE: ItemOpState = { phase: 'idle', failure: null }
const OFFLINE_MESSAGE = 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.'
const UNEXPECTED_MESSAGE = 'Terjadi galat tak terduga. Coba lagi.'

function kindOf(r: Extract<ListOpResult, { ok: false }>): ItemFailureKind {
  if (r.retryable) return 'network'
  return r.code === 'OFFLINE' || r.code === 'NO_CLIENT' ? 'offline' : 'rejected'
}

// Satu slot per barang: kunci double-submit per barang, op_id baru per niat baru, op_id sama untuk "Coba lagi" (SYNC-004).
// Tanpa optimistic update: nilai di layar berubah hanya setelah server menjawab dan data disegarkan (SYNC-006).
export function createItemOps(cfg: ItemOpsConfig) {
  const slots = new Map<string, Slot>()
  const listeners = new Set<() => void>()
  let last: LastOk | null = null
  let seq = 0

  const emit = () => listeners.forEach((l) => l())

  function slotOf(id: string): Slot {
    let s = slots.get(id)
    if (!s) {
      s = { runner: createAttemptRunner<SessionOpType>(cfg.submit, cfg.newId), state: IDLE, okText: '' }
      slots.set(id, s)
    }
    return s
  }

  const holdsAttempt = (s: Slot) => s.state.phase === 'failed' && s.runner.hasPending()

  function fail(s: Slot, failure: ItemFailure): RunOutcome {
    s.state = { phase: 'failed', failure }
    emit()
    return { status: 'failed', failure }
  }

  // Fase 'sending' dipasang sebelum await pertama, jadi klik ganda berikutnya langsung diabaikan.
  async function exec(s: Slot, go: () => Promise<ListOpResult | null>): Promise<RunOutcome> {
    s.state = { phase: 'sending', failure: null }
    emit()
    let r: ListOpResult | null
    try {
      r = await go()
    } catch {
      return fail(s, { kind: 'unexpected', code: 'UNEXPECTED', message: UNEXPECTED_MESSAGE, retryable: s.runner.hasPending() })
    }
    if (r === null) {
      s.state = IDLE
      emit()
      return { status: 'ignored' }
    }
    if (r.ok) {
      s.state = IDLE
      seq += 1
      last = { seq, text: s.okText }
      emit()
      return { status: 'ok' }
    }
    return fail(s, { kind: kindOf(r), code: r.code, message: r.message, retryable: r.retryable })
  }

  async function run(
    itemId: string,
    type: ItemOpType,
    payload: Record<string, unknown>,
    okText: string,
  ): Promise<RunOutcome> {
    const s = slotOf(itemId)
    if (s.state.phase === 'sending' || holdsAttempt(s)) return { status: 'ignored' }
    if (!cfg.isOnline()) {
      return fail(s, { kind: 'offline', code: 'OFFLINE', message: OFFLINE_MESSAGE, retryable: false })
    }
    s.okText = okText
    return exec(s, () => s.runner.run(type, payload))
  }

  async function retry(itemId: string): Promise<RunOutcome> {
    const s = slots.get(itemId)
    if (!s || !holdsAttempt(s)) return { status: 'ignored' }
    // Offline: jangan memanggil pengirim, supaya op_id yang menunggu tidak terbuang.
    if (!cfg.isOnline()) return { status: 'ignored' }
    return exec(s, () => s.runner.retry())
  }

  // Menutup galat penolakan, atau menghentikan percobaan yang menunggu (hasilnya tidak diketahui, jadi layar disegarkan).
  function dismiss(itemId: string): void {
    const s = slots.get(itemId)
    if (!s || s.state.phase === 'sending') return
    if (s.runner.hasPending()) {
      s.runner.discard()
      cfg.onDiscard?.()
    }
    s.state = IDLE
    emit()
  }

  function anyBusy(): boolean {
    for (const s of slots.values()) {
      if (s.state.phase === 'sending' || holdsAttempt(s)) return true
    }
    return false
  }

  return {
    getItem: (itemId: string): ItemOpState => slots.get(itemId)?.state ?? IDLE,
    getLast: (): LastOk | null => last,
    anyBusy,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    run,
    retry,
    dismiss,
  }
}

export type ItemOps = ReturnType<typeof createItemOps>
