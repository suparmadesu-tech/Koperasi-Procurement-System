import { createAttemptRunner } from '../daftar/attemptRunner'
import type { SubmitOptions } from '../daftar/submitCore'
import type { ListOpResult } from '../daftar/types'
import type { EndPlan, StartPlan } from './sessionGuards'
import type { SessionOpType } from './sessionRpc'

export type FlowAction = 'start' | 'end' | 'cancel'

// Hasil penjaga sebelum RPC: diblokir (tanpa RPC) atau lanjut ke konfirmasi, dengan peringatan opsional.
export type GuardOutcome =
  | { kind: 'blocked'; message: string }
  | { kind: 'ok'; note: string; warning: string | null }

export const startGuard =
  (check: () => Promise<StartPlan>) =>
  async (): Promise<GuardOutcome> => {
    const p = await check()
    return p.allowed ? { kind: 'ok', note: p.message, warning: null } : { kind: 'blocked', message: p.message }
  }

// Perubahan yang belum tersimpan tidak memblokir akhir sesi, tetapi wajib konfirmasi kedua (FR-028, SYNC-012).
export const endGuard =
  (check: () => Promise<EndPlan>) =>
  async (): Promise<GuardOutcome> => {
    const p = await check()
    return p.needsConfirm ? { kind: 'ok', note: '', warning: p.message } : { kind: 'ok', note: p.message, warning: null }
  }

export const noGuard = async (): Promise<GuardOutcome> => ({ kind: 'ok', note: '', warning: null })

export type FlowPhase = 'idle' | 'checking' | 'confirm' | 'confirm_warning' | 'sending' | 'failed' | 'done'
export type FlowFailureKind = 'guard' | 'offline' | 'network' | 'rejected' | 'unexpected'

export interface FlowFailure {
  kind: FlowFailureKind
  code: string
  message: string
  // true: ada percobaan yang menunggu kirim ulang dengan op_id sama, atau dihentikan pengguna.
  retryable: boolean
}

export interface FlowState {
  phase: FlowPhase
  // Catatan di dialog pertama (misalnya pengingat perangkat lain).
  note: string
  // Peringatan untuk konfirmasi kedua; null bila tidak perlu.
  warning: string | null
  failure: FlowFailure | null
  result: Record<string, unknown> | null
}

export type SettledOutcome = { ok: true; data: Record<string, unknown> } | { ok: false; failure: FlowFailure }

export interface FlowConfig {
  opType: SessionOpType
  payload: () => Record<string, unknown>
  guard: () => Promise<GuardOutcome>
  // Mulai sesi memeriksa antrean sekali lagi tepat sebelum kirim (FR-045).
  recheckBeforeSend: boolean
  submit: (type: SessionOpType, payload: Record<string, unknown>, options: SubmitOptions) => Promise<ListOpResult>
  isOnline: () => boolean
  newId: () => string
  onDiscard?: () => void
  onSettled?: (outcome: SettledOutcome) => void
}

const OFFLINE_MESSAGE = 'Anda sedang offline. Perubahan sesi belanja memerlukan koneksi internet.'
const UNEXPECTED_MESSAGE = 'Terjadi galat tak terduga. Coba lagi.'
const INITIAL: FlowState = { phase: 'idle', note: '', warning: null, failure: null, result: null }

// Pengendali alur tanpa React: kunci double-submit, kirim ulang dengan op_id sama (SYNC-004),
// dan pembedaan ditolak server dari gagal jaringan (SYNC-020). Status tidak "tersimpan" sebelum jawaban server (SYNC-006).
export function createSessionFlow(cfg: FlowConfig) {
  const runner = createAttemptRunner<SessionOpType>(cfg.submit, cfg.newId)
  let state: FlowState = INITIAL
  const listeners = new Set<() => void>()

  const set = (next: FlowState) => {
    state = next
    listeners.forEach((l) => l())
  }
  const busy = () => state.phase === 'checking' || state.phase === 'sending'

  function fail(failure: FlowFailure) {
    set({ ...state, phase: 'failed', failure, result: null })
    cfg.onSettled?.({ ok: false, failure })
  }

  const unexpected = (): FlowFailure => ({
    kind: 'unexpected',
    code: 'UNEXPECTED',
    message: UNEXPECTED_MESSAGE,
    retryable: runner.hasPending(),
  })

  function kindOf(r: Extract<ListOpResult, { ok: false }>): FlowFailureKind {
    if (r.retryable) return 'network'
    return r.code === 'OFFLINE' || r.code === 'NO_CLIENT' ? 'offline' : 'rejected'
  }

  // Fase 'sending' dipasang sebelum await pertama, jadi klik ganda berikutnya langsung ditolak.
  async function send(mode: 'run' | 'retry'): Promise<void> {
    set({ ...state, phase: 'sending', failure: null })
    try {
      if (cfg.recheckBeforeSend) {
        const g = await cfg.guard()
        if (g.kind === 'blocked') {
          fail({ kind: 'guard', code: 'BLOCKED', message: g.message, retryable: runner.hasPending() })
          return
        }
      }
      const r = mode === 'run' ? await runner.run(cfg.opType, cfg.payload()) : await runner.retry()
      if (r === null) {
        set(INITIAL)
        return
      }
      if (r.ok) {
        set({ ...state, phase: 'done', failure: null, result: r.data })
        cfg.onSettled?.({ ok: true, data: r.data })
        return
      }
      fail({ kind: kindOf(r), code: r.code, message: r.message, retryable: r.retryable })
    } catch {
      fail(unexpected())
    }
  }

  async function begin(): Promise<void> {
    const p = state.phase
    if (p === 'checking' || p === 'sending' || p === 'confirm' || p === 'confirm_warning') return
    // Masih ada percobaan menunggu: gunakan retry atau hentikan, jangan membuat op_id baru.
    if (p === 'failed' && runner.hasPending()) return
    if (!cfg.isOnline()) {
      fail({ kind: 'offline', code: 'OFFLINE', message: OFFLINE_MESSAGE, retryable: false })
      return
    }
    set({ ...INITIAL, phase: 'checking' })
    let g: GuardOutcome
    try {
      g = await cfg.guard()
    } catch {
      fail(unexpected())
      return
    }
    if (g.kind === 'blocked') {
      fail({ kind: 'guard', code: 'BLOCKED', message: g.message, retryable: false })
      return
    }
    set({ ...INITIAL, phase: 'confirm', note: g.note, warning: g.warning })
  }

  async function confirm(): Promise<void> {
    if (state.phase === 'confirm') {
      if (state.warning !== null) {
        set({ ...state, phase: 'confirm_warning' })
        return
      }
      await send('run')
      return
    }
    if (state.phase === 'confirm_warning') await send('run')
  }

  async function retry(): Promise<void> {
    if (state.phase !== 'failed' || !runner.hasPending()) return
    await send('retry')
  }

  function dismiss(): void {
    if (busy()) return
    if (runner.hasPending()) {
      runner.discard()
      cfg.onDiscard?.()
    }
    set(INITIAL)
  }

  return {
    getState: (): FlowState => state,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    begin,
    confirm,
    retry,
    dismiss,
    hasPending: (): boolean => runner.hasPending(),
  }
}

export type SessionFlow = ReturnType<typeof createSessionFlow>
