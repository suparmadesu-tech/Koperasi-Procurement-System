#!/usr/bin/env bash
# KPS Tahap 4, Bagian 3C: tambah barang ke sesi aktif (katalog dan manual).
# Ubah jumlah kebutuhan, hapus barang langsung, dan foto susulan (T-F) bukan bagian ini (3D).
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }

B=src/features/belanja
D=src/features/daftar

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
command -v python3 >/dev/null || fail "python3 tidak ditemukan"
command -v node >/dev/null || fail "node tidak ditemukan"
[ -f package.json ] || fail "jalankan dari root repo (package.json tidak ada)"

for f in src/components/ui.ts src/lib/money.ts \
  src/features/katalog/catalogStore.ts src/features/katalog/useCatalog.ts src/features/katalog/types.ts \
  "$D/attemptRunner.ts" "$D/submitCore.ts" "$D/types.ts" "$D/useOnline.ts" "$D/TextField.tsx" \
  "$D/validation.ts" "$D/catalogSearch.ts" "$D/photoFlow.ts" "$D/photoDeps.ts" "$D/pendingPhotos.ts" \
  "$B/ActiveSession.tsx" "$B/itemOps.ts" "$B/flowNotice.ts" "$B/sessionPayloads.ts" "$B/sessionValidation.ts" \
  "$B/sessionErrors.ts" "$B/sessionRpc.ts" "$B/sessionSync.ts" "$B/submitSessionOp.ts"; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
for f in sessionAdd.ts sessionAdd.test.ts sessionErrors3c.test.ts useAddToSession.ts AddFailure.tsx \
  SessionAddCatalogForm.tsx SessionAddManualForm.tsx AddToSession.tsx; do
  [ ! -e "$B/$f" ] || fail "$B/$f sudah ada; tidak ditimpa"
done
! grep -qF 'AddToSession' "$B/ActiveSession.tsx" || fail "$B/ActiveSession.tsx sudah memuat AddToSession"
! grep -qF 'KPS_PRODUCT_ARCHIVED' "$B/sessionErrors.ts" || fail "$B/sessionErrors.ts sudah memuat KPS_PRODUCT_ARCHIVED"

# Tanda tangan ekspor yang dipakai (bukan hanya keberadaan nama).
python3 - <<'PY'
import re, sys

def read(p):
    return open(p, encoding="utf-8").read()

CHECKS = [
  ("src/features/daftar/attemptRunner.ts", r"export function createAttemptRunner<T extends string = string>\(submit: Submit<T>, newId: \(\) => string\)"),
  ("src/features/daftar/attemptRunner.ts", r"run: \(type: T, payload: Payload\): Promise<ListOpResult>"),
  ("src/features/daftar/attemptRunner.ts", r"retry: async \(\): Promise<ListOpResult \| null>"),
  ("src/features/daftar/attemptRunner.ts", r"discard: \(\): void"),
  ("src/features/daftar/attemptRunner.ts", r"hasPending: \(\): boolean"),
  ("src/features/daftar/types.ts", r"export type ListOpResult\s*=\s*\|\s*\{ ok: true; opId: string; data: Record<string, unknown>; replayed: boolean \}\s*\|\s*\{ ok: false; opId: string; code: string; message: string; retryable: boolean \}"),
  ("src/features/daftar/useOnline.ts", r"export function useOnline\(\): boolean"),
  ("src/features/daftar/TextField.tsx", r"export function TextField\(\{[^}]*\}: \{\s*id: string\s*label: string\s*value: string\s*onChange: \(v: string\) => void\s*error\?: string \| undefined\s*hint\?: string \| undefined\s*inputMode\?: 'text' \| 'decimal' \| 'numeric' \| undefined\s*multiline\?: boolean \| undefined\s*readOnly\?: boolean \| undefined"),
  ("src/features/daftar/validation.ts", r"export interface ManualItemValue \{\s*name: string\s*unit: string\s*quantity: string\s*note: string \| null\s*\}"),
  ("src/features/daftar/validation.ts", r"export function validateManualItemForm\(input: \{\s*name: string\s*unit: string\s*quantityText: string\s*note: string\s*\}\): FormResult<ManualItemValue, ManualKey>"),
  ("src/features/daftar/catalogSearch.ts", r"export interface CatalogHit \{\s*id: string\s*name: string\s*unitName: string\s*allowFraction: boolean\s*price: string \| null\s*\}"),
  ("src/features/daftar/catalogSearch.ts", r"export interface SearchResult \{\s*hits: CatalogHit\[\]\s*total: number\s*activeCount: number\s*\}"),
  ("src/features/daftar/catalogSearch.ts", r"export function searchProducts\(data: CatalogData, query: string, limit: number\): SearchResult"),
  ("src/features/daftar/catalogSearch.ts", r"export function findHit\(data: CatalogData, id: string\): CatalogHit \| null"),
  ("src/features/daftar/photoFlow.ts", r"export interface PhotoFlowDeps \{"),
  ("src/features/daftar/photoFlow.ts", r"export type PhotoPrep\s*=\s*\|\s*\{ kind: 'none' \}\s*\|\s*\{ kind: 'ready'; path: string; blob: Blob; mime: string \}\s*\|\s*\{ kind: 'upload_failed'; blob: Blob; mime: string; message: string \}\s*\|\s*\{ kind: 'invalid'; message: string \}"),
  ("src/features/daftar/photoFlow.ts", r"export async function preparePhoto\(deps: PhotoFlowDeps, workspaceId: string, file: File \| null\): Promise<PhotoPrep>"),
  ("src/features/daftar/photoDeps.ts", r"export const photoDeps: PhotoFlowDeps"),
  ("src/features/daftar/pendingPhotos.ts", r"export function setPendingPhoto\(itemId: string, photo: PendingPhoto\): void"),
  ("src/features/daftar/pendingPhotos.ts", r"export interface PendingPhoto \{\s*blob: Blob\s*mime: string\s*\}"),
  ("src/features/katalog/useCatalog.ts", r"export function useCatalog\(workspaceId: string \| null\)"),
  ("src/features/katalog/catalogStore.ts", r"export const isOnline"),
  ("src/features/katalog/types.ts", r"export type Result<T>"),
  ("src/lib/money.ts", r"export function formatRupiah\(v: string \| number \| Decimal\): string"),
  ("src/components/ui.ts", r"export const btnPrimary"),
  ("src/components/ui.ts", r"export const btnSecondary"),
  ("src/features/belanja/itemOps.ts", r"export type SessionSubmit = \(\s*type: SessionOpType,\s*payload: Record<string, unknown>,\s*options: SubmitOptions,\s*\) => Promise<ListOpResult>"),
  ("src/features/belanja/flowNotice.ts", r"export interface FlowNotice \{\s*tone: 'info' \| 'error'\s*text: string\s*\}"),
  ("src/features/belanja/flowNotice.ts", r"export function setFlowNotice\(next: FlowNotice \| null\): void"),
  ("src/features/belanja/sessionPayloads.ts", r"export function addCatalogToSessionPayload\(\s*sessionId: string,\s*productId: string,\s*quantity: string,\s*note: string \| null,\s*\): Payload"),
  ("src/features/belanja/sessionPayloads.ts", r"export function addManualToSessionPayload\(input: \{\s*sessionId: string\s*id: string\s*name: string\s*unit: string\s*quantity: string\s*note: string \| null\s*photoPath: string \| null\s*\}\): Payload"),
  ("src/features/belanja/sessionValidation.ts", r"export function validateSessionCatalogForm\(input: \{\s*productId: string\s*quantityText: string\s*note: string\s*allowFraction: boolean\s*\}\): FormResult<\{ productId: string; quantity: string; note: string \| null \}, 'productId' \| 'quantity' \| 'note'>"),
  ("src/features/belanja/sessionValidation.ts", r"export \{ validateManualItemForm as validateSessionManualForm \} from '\.\./daftar/validation'"),
  ("src/features/belanja/sessionRpc.ts", r"export type DirectOp\s*=\s*\|\s*'kps_start_session'\s*\|\s*'kps_end_session'\s*\|\s*'kps_cancel_session'\s*\|\s*'kps_add_catalog_to_session'"),
  ("src/features/belanja/sessionRpc.ts", r"export type ApplyOp\s*=\s*\|\s*'session_add_manual'"),
  ("src/features/belanja/sessionRpc.ts", r"case 'kps_add_catalog_to_session': \{"),
  ("src/features/belanja/sessionSync.ts", r"export const requestSessionRefresh"),
  ("src/features/belanja/sessionErrors.ts", r"export function sessionMessageForCode\(code: string \| null \| undefined, serverMessage\?: string\): string"),
  ("src/features/belanja/submitSessionOp.ts", r"export function submitSessionOp\(\s*workspaceId: string,\s*opType: SessionOpType,\s*payload: Record<string, unknown>,\s*options: SubmitOptions = \{\},?\s*\): Promise<SessionOpResult>"),
  ("src/features/belanja/ActiveSession.tsx", r"export function ActiveSession\(\{\s*view,\s*photoUrls,\s*workspaceId,\s*sessionId,\s*items,\s*\}: \{\s*view: ActiveView\s*photoUrls: Record<string, string>\s*workspaceId: string\s*sessionId: string\s*items: SessionItemRow\[\]\s*\}\)"),
  ("src/features/belanja/ActiveSession.tsx", r"const online = useOnline\(\)"),
]

bad = []
for path, rx in CHECKS:
    if not re.search(rx, read(path)):
        bad.append("%s: tanda tangan tidak cocok: %s" % (path, rx))
if bad:
    sys.exit("BERHENTI:\n  " + "\n  ".join(bad))
PY

# Semua patch dicek dulu (tanpa menulis); diterapkan setelah berkas baru siap.
PATCHPY="$(mktemp)"
cat > "$PATCHPY" <<'PY'
import sys
check = len(sys.argv) > 1 and sys.argv[1] == "--check"
B = "src/features/belanja/"

EDITS = {
  B + "ActiveSession.tsx": [
    ("import { BulkPurchase } from './BulkPurchase'",
     "import { AddToSession } from './AddToSession'\nimport { BulkPurchase } from './BulkPurchase'"),
    ("      <BulkPurchase checklist={checklist} items={inCart} online={online} />",
     "      <BulkPurchase checklist={checklist} items={inCart} online={online} />\n\n      <AddToSession workspaceId={workspaceId} sessionId={sessionId} online={online} />"),
  ],
  B + "sessionErrors.ts": [
    ("  KPS_TOTAL_MISMATCH: 'Total sesi tidak cocok dengan hitungan server. Muat ulang lalu coba lagi.',",
     "  KPS_TOTAL_MISMATCH: 'Total sesi tidak cocok dengan hitungan server. Muat ulang lalu coba lagi.',\n"
     "  // Menambah barang ke sesi (FR-052): wording khusus sesi.\n"
     "  KPS_PRODUCT_ARCHIVED: 'Barang katalog ini sudah diarsipkan, jadi tidak dapat ditambahkan ke sesi.',\n"
     "  KPS_FRACTION_NOT_ALLOWED: 'Satuan barang ini tidak menerima jumlah berpecahan. Masukkan bilangan bulat.',\n"
     "  KPS_INVALID_QUANTITY: 'Jumlah harus lebih dari 0 dan paling banyak 3 angka di belakang koma.',\n"
     "  KPS_TEXT_TOO_LONG: 'Teks terlalu panjang. Nama maksimal 200 karakter, satuan 50, catatan 1000.',\n"
     "  KPS_CONFLICT: 'Barang dengan ID ini sudah ada di sesi. Muat ulang untuk melihatnya.',\n"
     "  KPS_PHOTO_NOT_FOUND: 'Berkas foto belum ada di penyimpanan, jadi barang belum ditambahkan. Coba lagi atau tambahkan tanpa foto.',\n"
     "  KPS_INVALID_PHOTO_PATH: 'Lokasi foto tidak valid, jadi barang belum ditambahkan. Coba lagi atau tambahkan tanpa foto.',"),
  ],
}

for path, edits in EDITS.items():
    s = open(path, encoding="utf-8").read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            sys.exit("BERHENTI: %s: pola cocok %d kali (harus 1): %r" % (path, n, old))
        s = s.replace(old, new)
    if not check:
        open(path, "w", encoding="utf-8").write(s)
PY
python3 "$PATCHPY" --check || { rm -f "$PATCHPY"; exit 1; }

# --- Penulisan berkas baru ---
cat > "$B/sessionAdd.ts" <<'EOF'
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
EOF

cat > "$B/sessionAdd.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { PhotoFlowDeps } from '../daftar/photoFlow'
import type { ListOpResult } from '../daftar/types'
import {
  addDoneMessage,
  addDoneTone,
  createSessionAdd,
  isSessionLevelCode,
  type AddConfig,
  type AddIntent,
  type AddPhase,
  type AddSettled,
} from './sessionAdd'

const ok = (opId: string, data: Record<string, unknown> = {}): ListOpResult => ({
  ok: true,
  opId,
  data,
  replayed: false,
})
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})

type ManualIntent = Extract<AddIntent, { kind: 'manual' }>
const catalog: AddIntent = { kind: 'catalog', productId: 'p1', name: 'Gula', quantity: '2', note: null }
const manual = (over: Partial<ManualIntent> = {}): ManualIntent => ({
  kind: 'manual',
  name: 'Plastik',
  unit: 'pak',
  quantity: '1.5',
  note: null,
  file: null,
  ...over,
})

function setup(over: Partial<AddConfig> = {}) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  const settled: AddSettled[] = []
  const mode = { compress: 'ok' as 'ok' | 'bad', upload: 'ok' as 'ok' | 'fail' }
  const counts = { compress: 0, upload: 0 }
  let op = 0
  let item = 0
  let discards = 0
  const blob = new Blob(['x'])
  const file = blob as unknown as File
  const photo: PhotoFlowDeps = {
    compress: async () => {
      counts.compress += 1
      return mode.compress === 'ok'
        ? { ok: true, data: { blob, mime: 'image/webp' } }
        : { ok: false, error: { code: 'PHOTO_TOO_LARGE', message: 'Foto terlalu besar.' } }
    },
    upload: async () => {
      counts.upload += 1
      return mode.upload === 'ok'
        ? { ok: true, data: `w1/foto-${counts.upload}.webp` }
        : { ok: false, error: { code: 'UPLOAD_FAILED', message: 'Tidak ada koneksi internet.' } }
    },
  }
  const add = createSessionAdd({
    workspaceId: 'w1',
    sessionId: 's1',
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    newId: () => `op-${++op}`,
    newItemId: () => `item-${++item}`,
    isOnline: () => true,
    photo,
    onDiscard: () => {
      discards += 1
    },
    onSettled: (o) => {
      settled.push(o)
    },
    ...over,
  })
  return { add, calls, results, settled, mode, counts, file, discards: () => discards }
}

describe('tambah barang katalog (FR-052, T-04)', () => {
  it('mengirim kps_add_catalog_to_session dengan payload sesi; id barang dari server; tanpa baris lokal', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'srv-9', price_snapshot: 5000 }))
    const done = await t.add.submit({ ...catalog, note: 'merah' } as AddIntent)
    expect(t.calls).toEqual([
      {
        type: 'kps_add_catalog_to_session',
        payload: { session_id: 's1', product_id: 'p1', quantity: 2, note: 'merah' },
        opId: 'op-1',
      },
    ])
    expect(done).toMatchObject({ kind: 'catalog', name: 'Gula', itemId: 'srv-9', photo: 'none' })
    expect(t.add.getState().phase).toBe('done')
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
  })

  it('produk yang sama ditambahkan dua kali: dua operasi terpisah, tidak digabung atau diblokir (T-D)', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'a' }), ok('op-2', { item_id: 'b' }))
    await t.add.submit(catalog)
    await t.add.submit(catalog)
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
    expect(t.calls.map((c) => c.payload.product_id)).toEqual(['p1', 'p1'])
  })

  it('catatan kosong tidak dikirim', async () => {
    const t = setup()
    t.results.push(ok('op-1'))
    await t.add.submit(catalog)
    expect(t.calls[0]?.payload).toEqual({ session_id: 's1', product_id: 'p1', quantity: 2 })
  })
})

describe('tambah barang manual (FR-052)', () => {
  it('mengirim session_add_manual dengan id dari klien tanpa foto', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual())
    expect(t.calls).toEqual([
      {
        type: 'session_add_manual',
        payload: { session_id: 's1', id: 'item-1', name: 'Plastik', unit: 'pak', quantity: 1.5 },
        opId: 'op-1',
      },
    ])
    expect(done).toMatchObject({ kind: 'manual', itemId: 'item-1', photo: 'none' })
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
  })

  it('foto berhasil diunggah: path baru ikut dikirim dan hasil menyebut foto terpasang setelah konfirmasi server', async () => {
    const t = setup()
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual({ file: t.file }))
    expect(t.calls[0]?.payload).toMatchObject({ id: 'item-1', photo_path: 'w1/foto-1.webp' })
    expect(done?.photo).toBe('attached')
    expect(addDoneMessage(done!)).toContain('dengan foto (dikonfirmasi server)')
  })
})

describe('foto gagal tetap menambah barang tanpa foto (FR-013, SYNC-019)', () => {
  it('unggah gagal: barang tetap dikirim tanpa photo_path, hasil kompres disimpan, dan pesan jujur', async () => {
    const t = setup()
    t.mode.upload = 'fail'
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const done = await t.add.submit(manual({ file: t.file }))
    expect(t.calls).toHaveLength(1)
    expect('photo_path' in (t.calls[0]?.payload ?? {})).toBe(false)
    expect(done).toMatchObject({ photo: 'failed', itemId: 'item-1', photoMessage: 'Tidak ada koneksi internet.' })
    expect(done?.pending?.mime).toBe('image/webp')
    const msg = addDoneMessage(done!)
    expect(msg).toContain('tanpa foto')
    expect(msg).toContain('Foto belum terpasang')
    expect(msg).not.toContain('dengan foto')
    expect(addDoneTone(done!)).toBe('error')
  })

  it('foto tidak dapat diproses (kompres gagal): tidak ada yang diunggah atau dikirim', async () => {
    const t = setup()
    t.mode.compress = 'bad'
    const done = await t.add.submit(manual({ file: t.file }))
    expect(done).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'photo', message: 'Foto terlalu besar.', retryable: false })
    expect(t.counts).toEqual({ compress: 1, upload: 0 })
    expect(t.calls).toHaveLength(0)

    t.mode.compress = 'ok'
    t.results.push(ok('op-1'))
    expect(await t.add.submit(manual({ file: t.file }))).not.toBeNull()
    expect(t.calls).toHaveLength(1)
  })
})

describe('kirim ulang dengan op_id dan id barang yang sama (SYNC-004)', () => {
  it('retry mengirim op_id, id barang, dan path foto yang sama; foto tidak diunggah ulang', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-1', { item_id: 'item-1' }))
    const first = await t.add.submit(manual({ file: t.file }))
    expect(first).toBeNull()
    expect(t.add.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.add.hasPending()).toBe(true)

    const done = await t.add.retry()
    expect(done).toMatchObject({ itemId: 'item-1', photo: 'attached' })
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.calls[0]).toMatchObject({ opId: 'op-1', payload: { id: 'item-1', photo_path: 'w1/foto-1.webp' } })
    expect(t.counts).toEqual({ compress: 1, upload: 1 })
    expect(t.add.hasPending()).toBe(false)
  })

  it('retry katalog memakai op_id dan payload yang sama', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-1', { item_id: 'srv' }))
    await t.add.submit(catalog)
    await t.add.retry()
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
  })

  it('retry yang gagal lagi tetap memakai op_id dan id yang sama', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), bad('x', 'NETWORK', true))
    await t.add.submit(manual())
    await t.add.retry()
    expect(t.add.getState().phase).toBe('failed')
    expect(t.calls.map((c) => `${c.opId}:${String(c.payload.id)}`)).toEqual(['op-1:item-1', 'op-1:item-1'])
  })

  it('selama percobaan menunggu, niat baru diabaikan: tidak ada op_id atau id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true))
    await t.add.submit(manual())
    expect(await t.add.submit(manual({ name: 'Lain' }))).toBeNull()
    expect(t.calls).toHaveLength(1)
  })

  it('retry saat offline tidak memanggil pengirim dan percobaan tetap tersimpan', async () => {
    let online = true
    const t = setup({ isOnline: () => online })
    t.results.push(bad('x', 'NETWORK', true), ok('op-1'))
    await t.add.submit(catalog)
    online = false
    expect(await t.add.retry()).toBeNull()
    expect(t.calls).toHaveLength(1)
    expect(t.add.getState().phase).toBe('failed')
    online = true
    expect(await t.add.retry()).not.toBeNull()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan niat berikutnya memakai op_id dan id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'NETWORK', true), ok('op-2'))
    await t.add.submit(manual())
    t.add.dismiss()
    expect(t.add.getState().phase).toBe('idle')
    expect(t.discards()).toBe(1)
    await t.add.submit(manual())
    expect(t.calls.map((c) => `${c.opId}:${String(c.payload.id)}`)).toEqual(['op-1:item-1', 'op-2:item-2'])
  })
})

describe('tanpa pengiriman ganda', () => {
  it('kirim berganda pada niat yang sama hanya mengirim satu operasi', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: async (_t, _p, o) => {
        sent.push(o.opId)
        return gate
      },
    })
    const p1 = t.add.submit(manual())
    const p2 = t.add.submit(manual())
    const p3 = t.add.submit(catalog)
    expect(t.add.getState().phase).toBe('sending')
    release(ok('op-1', { item_id: 'item-1' }))
    const out = await Promise.all([p1, p2, p3])
    expect(out[0]).not.toBeNull()
    expect(out[1]).toBeNull()
    expect(out[2]).toBeNull()
    expect(sent).toEqual(['op-1'])
  })

  it('kirim berganda saat foto diproses juga hanya satu niat', async () => {
    let releaseUpload!: () => void
    const uploadGate = new Promise<void>((res) => {
      releaseUpload = res
    })
    const blob = new Blob(['x'])
    const t = setup({
      photo: {
        compress: async () => ({ ok: true, data: { blob, mime: 'image/webp' } }),
        upload: async () => {
          await uploadGate
          return { ok: true, data: 'w1/a.webp' }
        },
      },
    })
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    const p1 = t.add.submit(manual({ file: blob as unknown as File }))
    const p2 = t.add.submit(manual({ file: blob as unknown as File }))
    expect(t.add.getState().phase).toBe('preparing')
    releaseUpload()
    await Promise.all([p1, p2])
    expect(t.calls).toHaveLength(1)
  })
})

describe('penolakan tidak dicoba ulang (SYNC-020)', () => {
  it('KPS_PRODUCT_ARCHIVED: tidak dapat diulang; niat baru memakai op_id baru', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_PRODUCT_ARCHIVED', false), ok('op-2', { item_id: 'b' }))
    expect(await t.add.submit(catalog)).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'rejected', code: 'KPS_PRODUCT_ARCHIVED', retryable: false })
    expect(t.add.hasPending()).toBe(false)
    expect(await t.add.retry()).toBeNull()
    expect(t.calls).toHaveLength(1)
    expect(await t.add.submit(catalog)).not.toBeNull()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('penolakan barang manual: id baru untuk niat berikutnya', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_TEXT_TOO_LONG', false), ok('op-2'))
    await t.add.submit(manual())
    await t.add.submit(manual())
    expect(t.calls.map((c) => String(c.payload.id))).toEqual(['item-1', 'item-2'])
  })

  it('kode sesi-level dipisahkan dari penolakan yang dapat diperbaiki di formulir', () => {
    expect(isSessionLevelCode('KPS_SESSION_NOT_ACTIVE')).toBe(true)
    expect(isSessionLevelCode('SESSION_EXPIRED')).toBe(true)
    for (const c of ['KPS_PRODUCT_ARCHIVED', 'KPS_FRACTION_NOT_ALLOWED', 'KPS_INVALID_QUANTITY', 'KPS_TEXT_TOO_LONG', 'KPS_CONFLICT', 'KPS_PHOTO_NOT_FOUND', 'KPS_INVALID_PHOTO_PATH']) {
      expect(isSessionLevelCode(c)).toBe(false)
    }
  })

  it('hasil akhir dilaporkan lewat onSettled: penolakan dan sukses', async () => {
    const t = setup()
    t.results.push(bad('x', 'KPS_SESSION_NOT_ACTIVE', false), ok('op-2', { item_id: 'b' }))
    await t.add.submit(catalog)
    await t.add.submit(catalog)
    expect(t.settled[0]).toMatchObject({ ok: false, failure: { kind: 'rejected', code: 'KPS_SESSION_NOT_ACTIVE' } })
    expect(t.settled[1]).toMatchObject({ ok: true, done: { itemId: 'b' } })
  })
})

describe('offline, galat tak terduga, dan fase', () => {
  it('offline: gagal tanpa memproses foto atau mengirim apa pun', async () => {
    const t = setup({ isOnline: () => false })
    const out = await t.add.submit(manual({ file: t.file }))
    expect(out).toBeNull()
    expect(t.add.getState().failure).toMatchObject({ kind: 'offline', code: 'OFFLINE', retryable: false })
    expect(t.counts).toEqual({ compress: 0, upload: 0 })
    expect(t.calls).toHaveLength(0)
  })

  it('galat tak terduga tidak membuat pengendali macet di fase sending', async () => {
    const t = setup()
    t.results.push(new Error('meledak'))
    expect(await t.add.submit(catalog)).toBeNull()
    expect(t.add.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'unexpected', retryable: false } })
    t.add.dismiss()
    expect(t.add.getState().phase).toBe('idle')
  })

  it('urutan fase barang manual dengan foto', async () => {
    const t = setup()
    const phases: AddPhase[] = []
    t.add.subscribe(() => phases.push(t.add.getState().phase))
    t.results.push(ok('op-1', { item_id: 'item-1' }))
    await t.add.submit(manual({ file: t.file }))
    expect(phases).toEqual(['preparing', 'sending', 'done'])
  })

  it('id barang manual jatuh ke id klien bila server tidak mengirim item_id', async () => {
    const t = setup()
    t.results.push(ok('op-1', {}))
    const done = await t.add.submit(manual())
    expect(done?.itemId).toBe('item-1')
  })
})

describe('teks hasil', () => {
  it('selalu menyebut dikonfirmasi server dan bahwa estimasi awal tidak berubah (BR-025)', () => {
    const base = { name: 'Gula', itemId: 'i', photoMessage: null, pending: null }
    for (const d of [
      { ...base, kind: 'catalog' as const, photo: 'none' as const },
      { ...base, kind: 'manual' as const, photo: 'none' as const },
      { ...base, kind: 'manual' as const, photo: 'attached' as const },
      { ...base, kind: 'manual' as const, photo: 'failed' as const },
    ]) {
      const m = addDoneMessage(d)
      expect(m).toContain('dikonfirmasi server')
      expect(m).toContain('Estimasi awal sesi tidak berubah.')
    }
  })
})
EOF

cat > "$B/sessionErrors3c.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { sessionMessageForCode } from './sessionErrors'

describe('pesan penolakan saat menambah barang ke sesi', () => {
  it('semua kode FR-052 punya pesan Indonesia sendiri, bukan pesan server', () => {
    const expected: Record<string, string> = {
      KPS_SESSION_NOT_ACTIVE: 'selesai atau dibatalkan',
      KPS_PRODUCT_ARCHIVED: 'diarsipkan',
      KPS_FRACTION_NOT_ALLOWED: 'berpecahan',
      KPS_INVALID_QUANTITY: 'lebih dari 0',
      KPS_TEXT_TOO_LONG: 'maksimal 200',
      KPS_CONFLICT: 'sudah ada di sesi',
      KPS_PHOTO_NOT_FOUND: 'belum ditambahkan',
      KPS_INVALID_PHOTO_PATH: 'tidak valid',
    }
    for (const [code, part] of Object.entries(expected)) {
      const m = sessionMessageForCode(code, 'PESAN-SERVER-ASING')
      expect(m).toContain(part)
      expect(m).not.toContain('PESAN-SERVER-ASING')
    }
  })

  it('pesan lama tidak berubah dan kode tak dikenal tetap jatuh ke pesan server', () => {
    expect(sessionMessageForCode('KPS_ITEM_DELETED')).toContain('dihapus dari sesi')
    expect(sessionMessageForCode('KPS_BARU', 'dari server')).toBe('dari server')
  })

  it('kegagalan foto tidak menyiratkan barang tersimpan', () => {
    expect(sessionMessageForCode('KPS_PHOTO_NOT_FOUND')).toContain('belum ditambahkan')
    expect(sessionMessageForCode('KPS_INVALID_PHOTO_PATH')).toContain('belum ditambahkan')
  })
})
EOF

cat > "$B/useAddToSession.ts" <<'EOF'
import { useMemo, useSyncExternalStore } from 'react'
import { photoDeps } from '../daftar/photoDeps'
import { isOnline } from '../katalog/catalogStore'
import { setFlowNotice } from './flowNotice'
import { createSessionAdd, isSessionLevelCode } from './sessionAdd'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

// Menghubungkan pengendali murni dengan titik tunggal penulisan sesi dan alur foto Tahap 3. Tidak ada pola baru.
export function useAddToSession(workspaceId: string, sessionId: string) {
  const add = useMemo(
    () =>
      createSessionAdd({
        workspaceId,
        sessionId,
        submit: (type, payload, options) => submitSessionOp(workspaceId, type, payload, options),
        newId: () => crypto.randomUUID(),
        newItemId: () => crypto.randomUUID(),
        isOnline,
        photo: photoDeps,
        // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
        onDiscard: requestSessionRefresh,
        // Sesi sudah berakhir: layar berpindah, jadi pesan dibawa ke spanduk halaman.
        onSettled: (o) => {
          if (!o.ok && o.failure.kind === 'rejected' && isSessionLevelCode(o.failure.code)) {
            setFlowNotice({ tone: 'error', text: o.failure.message })
          }
        },
      }),
    [workspaceId, sessionId],
  )
  const state = useSyncExternalStore(add.subscribe, add.getState, add.getState)
  return { add, state }
}
EOF

cat > "$B/AddFailure.tsx" <<'EOF'
import { btnSecondary } from '../../components/ui'
import { isSessionLevelCode, type AddState } from './sessionAdd'

// Galat penambahan di dekat formulir. Galat foto tampil di kolom foto; penolakan sesi-level di spanduk halaman.
export function AddFailure({
  state,
  online,
  onRetry,
  onDismiss,
}: {
  state: AddState
  online: boolean
  onRetry: () => void
  onDismiss: () => void
}) {
  const f = state.failure
  if (state.phase !== 'failed' || f === null || f.kind === 'photo') return null
  if (f.kind === 'rejected' && isSessionLevelCode(f.code)) return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      <p className="break-words">{f.message}</p>
      {f.retryable ? (
        <>
          <p>
            Belum ada konfirmasi dari server, jadi barang ini mungkin sudah atau belum ditambahkan. Mengirim ulang aman
            dan tidak menggandakan barang.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={onRetry} disabled={!online}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={onDismiss}>
              Hentikan percobaan
            </button>
          </div>
          <p className="text-xs">Setelah dihentikan, layar disegarkan dari server untuk melihat hasil sebenarnya.</p>
        </>
      ) : (
        <button type="button" className={btnSecondary} onClick={onDismiss}>
          Tutup
        </button>
      )}
    </div>
  )
}
EOF

cat > "$B/SessionAddCatalogForm.tsx" <<'EOF'
import { useMemo, useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { formatRupiah } from '../../lib/money'
import { searchProducts, type CatalogHit } from '../daftar/catalogSearch'
import { TextField } from '../daftar/TextField'
import { useCatalog } from '../katalog/useCatalog'
import { AddFailure } from './AddFailure'
import { addDoneMessage, addDoneTone, type AddDone } from './sessionAdd'
import { validateSessionCatalogForm } from './sessionValidation'
import { useAddToSession } from './useAddToSession'

const RESULT_LIMIT = 8

type Errors = Partial<Record<'productId' | 'quantity' | 'note', string>>

export function SessionAddCatalogForm({
  workspaceId,
  sessionId,
  online,
  onDone,
  onCancel,
}: {
  workspaceId: string
  sessionId: string
  online: boolean
  onDone: (message: string, tone: 'info' | 'error') => void
  onCancel: () => void
}) {
  const { data } = useCatalog(workspaceId)
  const { add, state } = useAddToSession(workspaceId, sessionId)
  const [query, setQuery] = useState('')
  // Salinan pilihan, bukan id: pilihan tidak hilang bila katalog berubah saat percobaan menunggu.
  const [chosen, setChosen] = useState<CatalogHit | null>(null)
  const [qtyText, setQtyText] = useState('1')
  const [note, setNote] = useState('')
  const [errors, setErrors] = useState<Errors>({})

  const search = useMemo(() => (data ? searchProducts(data, query, RESULT_LIMIT) : null), [data, query])
  const busy = state.phase === 'sending'
  const awaiting = state.phase === 'failed' && state.failure !== null && state.failure.retryable
  const locked = busy || awaiting

  function finish(done: AddDone | null) {
    if (done) onDone(addDoneMessage(done), addDoneTone(done))
  }

  async function submit() {
    if (!chosen) return
    const v = validateSessionCatalogForm({
      productId: chosen.id,
      quantityText: qtyText,
      note,
      allowFraction: chosen.allowFraction,
    })
    if (!v.ok) {
      setErrors(v.errors)
      return
    }
    setErrors({})
    finish(
      await add.submit({
        kind: 'catalog',
        productId: v.value.productId,
        name: chosen.name,
        quantity: v.value.quantity,
        note: v.value.note,
      }),
    )
  }

  if (!data || !search) return <p role="status">Memuat katalog dari perangkat...</p>

  if (search.activeCount === 0) {
    return (
      <div className="space-y-3">
        <p className="text-sm">
          Katalog belum memiliki barang aktif. Admin perlu menambahkan barang di menu Katalog lebih dulu, atau gunakan
          barang manual.
        </p>
        <button type="button" className={btnSecondary} onClick={onCancel}>
          Tutup
        </button>
      </div>
    )
  }

  if (!chosen) {
    return (
      <div className="space-y-3">
        <TextField id="sesi-cari-katalog" label="Cari barang di katalog" value={query} onChange={setQuery} />
        {search.hits.length === 0 ? (
          <p className="text-sm">Tidak ada barang aktif yang cocok dengan pencarian.</p>
        ) : (
          <ul className="space-y-2">
            {search.hits.map((h) => (
              <li key={h.id}>
                <button
                  type="button"
                  onClick={() => setChosen(h)}
                  className="flex min-h-12 w-full cursor-pointer flex-col items-start rounded-md bg-white px-3 py-2 text-left ring-1 ring-black/25 hover:bg-black/5 active:bg-black/10"
                >
                  <span className="break-words font-semibold">{h.name}</span>
                  <span className="text-sm">
                    {h.unitName}
                    {h.price !== null ? ` · ${formatRupiah(h.price)}` : ' · Harga belum tersedia'}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
        {search.total > search.hits.length ? (
          <p className="text-xs text-ink/75">
            Menampilkan {search.hits.length} dari {search.total} barang. Persempit pencarian untuk melihat yang lain.
          </p>
        ) : null}
        <button type="button" className={btnSecondary} onClick={onCancel}>
          Batal
        </button>
      </div>
    )
  }

  return (
    <form
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        void submit()
      }}
      className="space-y-3"
    >
      <div className="space-y-2 rounded-md bg-black/5 p-3">
        <p className="break-words font-semibold">{chosen.name}</p>
        <p className="text-sm">
          {chosen.unitName}
          {chosen.price !== null ? ` · ${formatRupiah(chosen.price)}` : ' · Harga belum tersedia'}
        </p>
        <button type="button" className={btnSecondary} onClick={() => setChosen(null)} disabled={locked}>
          Ganti barang
        </button>
      </div>
      <TextField
        id="sesi-katalog-jumlah"
        label="Jumlah"
        value={qtyText}
        onChange={setQtyText}
        error={errors.quantity}
        inputMode={chosen.allowFraction ? 'decimal' : 'numeric'}
        hint={
          chosen.allowFraction
            ? 'Boleh berpecahan, maksimal 3 angka di belakang koma.'
            : 'Satuan ini hanya menerima bilangan bulat.'
        }
        readOnly={locked}
      />
      <TextField
        id="sesi-katalog-catatan"
        label="Catatan (opsional)"
        value={note}
        onChange={setNote}
        error={errors.note}
        multiline
        readOnly={locked}
      />
      <p className="text-xs text-ink/75">
        Barang yang sama boleh ditambahkan lagi; setiap penambahan menjadi baris terpisah. Harga katalog saat ini
        menjadi harga awal sesi, dan estimasi awal sesi tidak berubah.
      </p>
      <AddFailure
        state={state}
        online={online}
        onRetry={() => void add.retry().then(finish)}
        onDismiss={() => add.dismiss()}
      />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={btnPrimary} disabled={locked || !online}>
          {busy ? 'Menyimpan...' : 'Tambahkan ke sesi'}
        </button>
        <button type="button" className={btnSecondary} onClick={onCancel} disabled={locked}>
          Batal
        </button>
      </div>
      {!online ? <p className="text-sm">Anda sedang offline. Menambah barang ke sesi memerlukan koneksi internet.</p> : null}
    </form>
  )
}
EOF

cat > "$B/SessionAddManualForm.tsx" <<'EOF'
import { useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { setPendingPhoto } from '../daftar/pendingPhotos'
import { TextField } from '../daftar/TextField'
import { AddFailure } from './AddFailure'
import { addDoneMessage, addDoneTone, type AddDone } from './sessionAdd'
import { validateSessionManualForm } from './sessionValidation'
import { useAddToSession } from './useAddToSession'

type FieldKey = 'name' | 'unit' | 'quantity' | 'note'

export function SessionAddManualForm({
  workspaceId,
  sessionId,
  online,
  onDone,
  onCancel,
}: {
  workspaceId: string
  sessionId: string
  online: boolean
  onDone: (message: string, tone: 'info' | 'error') => void
  onCancel: () => void
}) {
  const { add, state } = useAddToSession(workspaceId, sessionId)
  const [name, setName] = useState('')
  const [qty, setQty] = useState('1')
  const [unit, setUnit] = useState('')
  const [note, setNote] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [errors, setErrors] = useState<Partial<Record<FieldKey, string>>>({})

  const preparing = state.phase === 'preparing'
  const busy = state.phase === 'sending'
  const awaiting = state.phase === 'failed' && state.failure !== null && state.failure.retryable
  const locked = preparing || busy || awaiting
  const photoError = state.failure !== null && state.failure.kind === 'photo' ? state.failure.message : null

  function finish(done: AddDone | null) {
    if (!done) return
    // Foto yang gagal diunggah disimpan di memori untuk pemasangan susulan.
    if (done.pending && done.itemId) setPendingPhoto(done.itemId, done.pending)
    onDone(addDoneMessage(done), addDoneTone(done))
  }

  async function submit() {
    const v = validateSessionManualForm({ name, unit, quantityText: qty, note })
    if (!v.ok) {
      setErrors(v.errors)
      return
    }
    setErrors({})
    finish(await add.submit({ kind: 'manual', ...v.value, file }))
  }

  return (
    <form
      noValidate
      onSubmit={(e) => {
        e.preventDefault()
        void submit()
      }}
      className="space-y-3"
    >
      <TextField id="sesi-manual-nama" label="Nama barang" value={name} onChange={setName} error={errors.name} readOnly={locked} />
      <TextField
        id="sesi-manual-jumlah"
        label="Jumlah"
        value={qty}
        onChange={setQty}
        error={errors.quantity}
        inputMode="decimal"
        hint="Boleh berpecahan, maksimal 3 angka di belakang koma."
        readOnly={locked}
      />
      <TextField
        id="sesi-manual-satuan"
        label="Satuan"
        value={unit}
        onChange={setUnit}
        error={errors.unit}
        hint="Contoh: kg, pak, pcs."
        readOnly={locked}
      />
      <TextField
        id="sesi-manual-catatan"
        label="Catatan (opsional)"
        value={note}
        onChange={setNote}
        error={errors.note}
        multiline
        readOnly={locked}
      />
      <div className="space-y-1">
        <label htmlFor="sesi-manual-foto" className="block text-sm font-semibold">
          Foto (opsional)
        </label>
        <input
          id="sesi-manual-foto"
          type="file"
          accept="image/*"
          disabled={locked}
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          className="block w-full text-base file:mr-3 file:min-h-12 file:cursor-pointer file:rounded-md file:border-0 file:bg-white file:px-4 file:ring-1 file:ring-black/25"
        />
        <p className="text-xs text-ink/75">
          Bila foto gagal diunggah, barang tetap ditambahkan tanpa foto dan Anda diberi tahu.
        </p>
        {photoError ? (
          <p role="alert" className="text-sm text-red-900">
            {photoError}
          </p>
        ) : null}
      </div>
      <p className="text-xs text-ink/75">
        Barang manual tidak memiliki harga awal. Harga aktual dapat diisi setelah barang ditambahkan. Estimasi awal sesi
        tidak berubah.
      </p>
      <AddFailure
        state={state}
        online={online}
        onRetry={() => void add.retry().then(finish)}
        onDismiss={() => add.dismiss()}
      />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={btnPrimary} disabled={locked || !online}>
          {preparing ? 'Memproses foto...' : busy ? 'Menyimpan...' : 'Tambahkan ke sesi'}
        </button>
        <button type="button" className={btnSecondary} onClick={onCancel} disabled={locked}>
          Batal
        </button>
      </div>
      {!online ? <p className="text-sm">Anda sedang offline. Menambah barang ke sesi memerlukan koneksi internet.</p> : null}
    </form>
  )
}
EOF

cat > "$B/AddToSession.tsx" <<'EOF'
import { useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { SessionAddCatalogForm } from './SessionAddCatalogForm'
import { SessionAddManualForm } from './SessionAddManualForm'

type Mode = 'closed' | 'catalog' | 'manual'
type Feedback = { text: string; tone: 'info' | 'error' }

export function AddToSession({
  workspaceId,
  sessionId,
  online,
}: {
  workspaceId: string
  sessionId: string
  online: boolean
}) {
  const [mode, setMode] = useState<Mode>('closed')
  const [feedback, setFeedback] = useState<Feedback | null>(null)

  const done = (text: string, tone: 'info' | 'error') => {
    setMode('closed')
    setFeedback({ text, tone })
  }
  const open = (next: Exclude<Mode, 'closed'>) => {
    setFeedback(null)
    setMode(next)
  }

  return (
    <section aria-labelledby="tambah-ke-sesi" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="tambah-ke-sesi" className="font-semibold">
        Tambah barang ke sesi
      </h2>

      {mode === 'closed' ? (
        <>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnPrimary} onClick={() => open('catalog')} disabled={!online}>
              Tambah dari katalog
            </button>
            <button type="button" className={btnSecondary} onClick={() => open('manual')} disabled={!online}>
              Tambah barang manual
            </button>
          </div>
          {!online ? (
            <p className="text-sm">Anda sedang offline. Menambah barang ke sesi memerlukan koneksi internet.</p>
          ) : (
            <p className="text-xs text-ink/75">
              Barang yang ditambahkan langsung ke sesi tidak masuk daftar kebutuhan dan tidak mengubah estimasi awal
              sesi.
            </p>
          )}
        </>
      ) : mode === 'catalog' ? (
        <div className="space-y-3">
          <h3 className="font-semibold">Tambah dari katalog</h3>
          <SessionAddCatalogForm
            workspaceId={workspaceId}
            sessionId={sessionId}
            online={online}
            onDone={done}
            onCancel={() => setMode('closed')}
          />
        </div>
      ) : (
        <div className="space-y-3">
          <h3 className="font-semibold">Tambah barang manual</h3>
          <SessionAddManualForm
            workspaceId={workspaceId}
            sessionId={sessionId}
            online={online}
            onDone={done}
            onCancel={() => setMode('closed')}
          />
        </div>
      )}

      {feedback ? (
        <div
          role={feedback.tone === 'error' ? 'alert' : 'status'}
          className={`flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ${
            feedback.tone === 'error' ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
          }`}
        >
          <p className="min-w-0 break-words">{feedback.text}</p>
          <button
            type="button"
            className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
            onClick={() => setFeedback(null)}
          >
            Tutup
          </button>
        </div>
      ) : null}
    </section>
  )
}
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run && npm run build"
