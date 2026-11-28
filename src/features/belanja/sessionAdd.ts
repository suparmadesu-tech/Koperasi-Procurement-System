import { createAttemptRunner } from '../daftar/attemptRunner'
import { preparePhoto, type PhotoFlowDeps } from '../daftar/photoFlow'
import type { ListOpResult } from '../daftar/types'
import type { SessionSubmit } from './itemOps'
import { addCatalogToSessionPayload, addManualToSessionPayload } from './sessionPayloads'
import type { SessionOpType } from './sessionRpc'

type ManualIntent = {
  kind: 'manual'
  name: string
  unit: string
  quantity: string
  note: string | null
  file: File | null
}
type CatalogIntent = { kind: 'catalog'; productId: string; name: string; quantity: string; note: string | null }
export type AddIntent = CatalogIntent | ManualIntent

export type AddPhase = 'idle' | 'preparing' | 'sending' | 'failed' | 'done'
// 'photo': foto tidak dapat diproses, tidak ada yang dikirim. Lainnya mengikuti SYNC-020.
export type AddFailureKind = 'photo' | 'offline' | 'network' | 'rejected' | 'unexpected'

export interface AddFailure {
  kind: AddFailureKind
  code: string
  message: string
  // true: percobaan menunggu kirim ulang dengan op_id dan id barang yang sama, atau dihentikan pengguna.
  retryable: boolean
}

export type AddPhoto = 'none' | 'attached' | 'failed'

export interface AddDone {
  kind: 'catalog' | 'manual'
  name: string
  // id barang sesi: dari jawaban server, atau id yang dibuat klien untuk barang manual.
  itemId: string | null
  photo: AddPhoto
  photoMessage: string | null
  // Hasil kompres yang gagal diunggah; disimpan untuk pemasangan susulan (3D).
  pending: { blob: Blob; mime: string } | null
}

export interface AddState {
  phase: AddPhase
  failure: AddFailure | null
  done: AddDone | null
}

export type AddSettled = { ok: true; done: AddDone } | { ok: false; failure: AddFailure }

export interface AddConfig {
  workspaceId: string
  sessionId: string
  submit: SessionSubmit
  // op_id operasi.
  newId: () => string
  // id baris barang manual (UUID dari klien); tetap sama untuk "Coba lagi" (FR-052, SYNC-004).
  newItemId: () => string
  isOnline: () => boolean
  photo: PhotoFlowDeps
  onDiscard?: () => void
  onSettled?: (outcome: AddSettled) => void
}

const INITIAL: AddState = { phase: 'idle', failure: null, done: null }
const OFFLINE_MESSAGE = 'Anda sedang offline. Menambah barang ke sesi memerlukan koneksi internet.'
const UNEXPECTED_MESSAGE = 'Terjadi galat tak terduga. Coba lagi.'

// Penolakan yang mengubah layar (sesi sudah berakhir) tampil di spanduk halaman; sisanya di dekat formulir.
const SESSION_LEVEL_CODES = ['KPS_SESSION_NOT_ACTIVE', 'KPS_SESSION_FROZEN', 'SESSION_EXPIRED']
export const isSessionLevelCode = (code: string): boolean => SESSION_LEVEL_CODES.includes(code)

// Teks hanya dipakai setelah jawaban server diterima (SYNC-006). Penambahan tidak mengubah estimasi awal (BR-025).
export function addDoneMessage(d: AddDone): string {
  const tail = 'Estimasi awal sesi tidak berubah.'
  if (d.kind === 'manual' && d.photo === 'failed') {
    return `${d.name} ditambahkan ke sesi (dikonfirmasi server) tanpa foto. ${d.photoMessage ?? 'Foto gagal diunggah.'} Foto belum terpasang pada barang ini. ${tail}`
  }
  if (d.kind === 'manual' && d.photo === 'attached') {
    return `${d.name} ditambahkan ke sesi dengan foto (dikonfirmasi server). ${tail}`
  }
  return `${d.name} ditambahkan ke sesi (dikonfirmasi server). ${tail}`
}

export const addDoneTone = (d: AddDone): 'info' | 'error' => (d.photo === 'failed' ? 'error' : 'info')

function kindOf(r: Extract<ListOpResult, { ok: false }>): AddFailureKind {
  if (r.retryable) return 'network'
  return r.code === 'OFFLINE' || r.code === 'NO_CLIENT' ? 'offline' : 'rejected'
}

// Satu penambahan = satu niat: op_id baru per niat, op_id dan id barang yang sama untuk "Coba lagi" (SYNC-004).
// Server membuat snapshot; klien tidak membuat baris lokal. Produk yang sama boleh ditambahkan berkali-kali (T-D).
export function createSessionAdd(cfg: AddConfig) {
  const runner = createAttemptRunner<SessionOpType>(cfg.submit, cfg.newId)
  let state: AddState = INITIAL
  let inflight: AddDone | null = null
  const listeners = new Set<() => void>()

  const set = (next: AddState) => {
    state = next
    listeners.forEach((l) => l())
  }
  const busy = () => state.phase === 'preparing' || state.phase === 'sending'

  function fail(failure: AddFailure): null {
    set({ phase: 'failed', failure, done: null })
    cfg.onSettled?.({ ok: false, failure })
    return null
  }

  const unexpected = (): AddFailure => ({
    kind: 'unexpected',
    code: 'UNEXPECTED',
    message: UNEXPECTED_MESSAGE,
    retryable: runner.hasPending(),
  })

  function settle(r: ListOpResult): AddDone | null {
    if (!r.ok) return fail({ kind: kindOf(r), code: r.code, message: r.message, retryable: r.retryable })
    const flight = inflight
    const fromServer = typeof r.data.item_id === 'string' ? r.data.item_id : null
    const done: AddDone = {
      kind: flight?.kind ?? 'catalog',
      name: flight?.name ?? '',
      itemId: fromServer ?? flight?.itemId ?? null,
      photo: flight?.photo ?? 'none',
      photoMessage: flight?.photoMessage ?? null,
      pending: flight?.pending ?? null,
    }
    inflight = null
    set({ phase: 'done', failure: null, done })
    cfg.onSettled?.({ ok: true, done })
    return done
  }

  // Fase dipasang sebelum await pertama, jadi kirim ganda berikutnya langsung diabaikan.
  async function submit(intent: AddIntent): Promise<AddDone | null> {
    const p = state.phase
    if (p === 'preparing' || p === 'sending') return null
    // Masih ada percobaan menunggu: gunakan retry atau hentikan, jangan membuat op_id dan id baru.
    if (p === 'failed' && runner.hasPending()) return null
    if (!cfg.isOnline()) return fail({ kind: 'offline', code: 'OFFLINE', message: OFFLINE_MESSAGE, retryable: false })

    const file = intent.kind === 'manual' ? intent.file : null
    set({ phase: file ? 'preparing' : 'sending', failure: null, done: null })
    try {
      let photoPath: string | null = null
      let photo: AddPhoto = 'none'
      let pending: AddDone['pending'] = null
      let photoMessage: string | null = null

      if (intent.kind === 'manual' && file) {
        // Unggah ke path baru lebih dulu (FR-013). Gagal unggah tidak membatalkan barangnya.
        const prep = await preparePhoto(cfg.photo, cfg.workspaceId, file)
        if (prep.kind === 'invalid') {
          return fail({ kind: 'photo', code: 'PHOTO_INVALID', message: prep.message, retryable: false })
        }
        if (prep.kind === 'ready') {
          photoPath = prep.path
          photo = 'attached'
        } else if (prep.kind === 'upload_failed') {
          photo = 'failed'
          pending = { blob: prep.blob, mime: prep.mime }
          photoMessage = prep.message
        }
        set({ ...state, phase: 'sending' })
      }

      const itemId = intent.kind === 'manual' ? cfg.newItemId() : null
      inflight = { kind: intent.kind, name: intent.name, itemId, photo, photoMessage, pending }
      const r =
        intent.kind === 'catalog'
          ? await runner.run(
              'kps_add_catalog_to_session',
              addCatalogToSessionPayload(cfg.sessionId, intent.productId, intent.quantity, intent.note),
            )
          : await runner.run(
              'session_add_manual',
              addManualToSessionPayload({
                sessionId: cfg.sessionId,
                id: itemId ?? cfg.newItemId(),
                name: intent.name,
                unit: intent.unit,
                quantity: intent.quantity,
                note: intent.note,
                photoPath,
              }),
            )
      return settle(r)
    } catch {
      return fail(unexpected())
    }
  }

  async function retry(): Promise<AddDone | null> {
    if (state.phase !== 'failed' || !runner.hasPending()) return null
    // Offline: jangan memanggil pengirim, supaya op_id yang menunggu tidak terbuang.
    if (!cfg.isOnline()) return null
    set({ ...state, phase: 'sending', failure: null })
    try {
      const r = await runner.retry()
      if (r === null) {
        set(INITIAL)
        return null
      }
      return settle(r)
    } catch {
      return fail(unexpected())
    }
  }

  // Menutup galat, atau menghentikan percobaan yang menunggu (hasilnya tidak diketahui, jadi layar disegarkan).
  function dismiss(): void {
    if (busy()) return
    if (runner.hasPending()) {
      runner.discard()
      cfg.onDiscard?.()
    }
    inflight = null
    set(INITIAL)
  }

  return {
    getState: (): AddState => state,
    subscribe: (listener: () => void): (() => void) => {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    submit,
    retry,
    dismiss,
    hasPending: (): boolean => runner.hasPending(),
  }
}

export type SessionAdd = ReturnType<typeof createSessionAdd>
