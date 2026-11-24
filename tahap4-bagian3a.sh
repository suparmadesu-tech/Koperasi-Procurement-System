#!/usr/bin/env bash
# KPS Tahap 4, Bagian 3A: siklus sesi (mulai, akhiri, batalkan).
# Checklist, harga/jumlah aktual, dan tambah barang ke sesi bukan bagian ini (3B dan 3C).
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }

B=src/features/belanja
D=src/features/daftar

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
command -v python3 >/dev/null || fail "python3 tidak ditemukan"
command -v node >/dev/null || fail "node tidak ditemukan"
[ -f package.json ] || fail "jalankan dari root repo (package.json tidak ada)"

for f in src/components/ConfirmDialog.tsx src/components/ui.ts src/lib/money.ts src/lib/queue.ts \
  src/lib/pending-ops.ts src/features/katalog/catalogStore.ts \
  "$D/attemptRunner.ts" "$D/submitCore.ts" "$D/types.ts" "$D/useOnline.ts" "$D/listView.ts" \
  "$B/BelanjaView.tsx" "$B/ActiveSession.tsx" "$B/NoSessionView.tsx" "$B/submitSessionOp.ts" \
  "$B/sessionGuards.ts" "$B/sessionGuardsLive.ts" "$B/sessionGuards.test.ts" "$B/sessionPayloads.ts" \
  "$B/sessionRpc.ts" "$B/sessionMath.ts" "$B/sessionSync.ts" "$B/types.ts"; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
for f in sessionFlow.ts sessionFlow.test.ts flowNotice.ts flowNotice.test.ts flowText.ts flowText.test.ts \
  useSessionFlow.ts FlowNoticeBanner.tsx FlowFailure.tsx StartSession.tsx SessionActions.tsx \
  sessionGuardsLive.test.ts; do
  [ ! -e "$B/$f" ] || fail "$B/$f sudah ada; tidak ditimpa"
done
for f in StartSession SessionActions FlowNoticeBanner; do
  ! grep -qF "$f" "$B/BelanjaView.tsx" "$B/NoSessionView.tsx" "$B/ActiveSession.tsx" \
    || fail "$f sudah dipakai di berkas yang akan di-patch"
done

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
  ("src/features/daftar/submitCore.ts", r"export interface SubmitOptions \{[^}]*opId\?: string"),
  ("src/features/daftar/types.ts", r"export type ListOpResult\s*=\s*\|\s*\{ ok: true; opId: string; data: Record<string, unknown>; replayed: boolean \}\s*\|\s*\{ ok: false; opId: string; code: string; message: string; retryable: boolean \}"),
  ("src/features/daftar/useOnline.ts", r"export function useOnline\(\): boolean"),
  ("src/features/daftar/listView.ts", r"export const unpricedLabel = \(n: number\): string =>"),
  ("src/features/daftar/listView.ts", r"export interface ListSummary \{[^}]*total: string[^}]*unpricedCount: number[^}]*itemCount: number"),
  ("src/features/katalog/catalogStore.ts", r"export const isOnline"),
  ("src/lib/money.ts", r"export function formatRupiah\(v: string \| number \| Decimal\): string"),
  ("src/lib/queue.ts", r"export async function countBlockingOps\("),
  ("src/lib/pending-ops.ts", r"export async function countPendingOps\("),
  ("src/components/ui.ts", r"export const btnPrimary"),
  ("src/components/ui.ts", r"export const btnSecondary"),
  ("src/components/ConfirmDialog.tsx", r"export default function ConfirmDialog\(props: Props\)"),
  ("src/components/ConfirmDialog.tsx", r"open: boolean;\s*title: string;\s*message: string;\s*confirmLabel: string;\s*cancelLabel: string;\s*onConfirm: \(\) => void;\s*onCancel: \(\) => void;"),
  ("src/features/belanja/submitSessionOp.ts", r"export function submitSessionOp\(\s*workspaceId: string,\s*opType: SessionOpType,\s*payload: Record<string, unknown>,\s*options: SubmitOptions = \{\},?\s*\): Promise<SessionOpResult>"),
  ("src/features/belanja/sessionRpc.ts", r"export type DirectOp\s*=\s*\|\s*'kps_start_session'\s*\|\s*'kps_end_session'\s*\|\s*'kps_cancel_session'"),
  ("src/features/belanja/sessionRpc.ts", r"export type SessionOpType = DirectOp \| ApplyOp"),
  ("src/features/belanja/sessionGuards.ts", r"export interface StartPlan \{\s*allowed: boolean\s*message: string\s*\}"),
  ("src/features/belanja/sessionGuards.ts", r"export interface EndPlan \{\s*needsConfirm: boolean\s*message: string\s*\}"),
  ("src/features/belanja/sessionGuards.ts", r"export function planEnd\(pending: number \| null\): EndPlan"),
  ("src/features/belanja/sessionGuards.ts", r"export async function checkStart\(count: \(\) => Promise<number>\): Promise<StartPlan>"),
  ("src/features/belanja/sessionGuards.ts", r"export async function checkEnd\(count: \(\) => Promise<number>\): Promise<EndPlan>"),
  ("src/features/belanja/sessionGuardsLive.ts", r"export const checkStartLive = \(\) => checkStart\(\(\) => countBlockingOps\(\)\)"),
  ("src/features/belanja/sessionGuardsLive.ts", r"export const checkEndLive = \(\) => checkEnd\(\(\) => countPendingOps\(\)\)"),
  ("src/features/belanja/sessionPayloads.ts", r"export const startSessionPayload = \(\): Payload =>"),
  ("src/features/belanja/sessionPayloads.ts", r"export const endSessionPayload = \(sessionId: string\): Payload =>"),
  ("src/features/belanja/sessionPayloads.ts", r"export const cancelSessionPayload = \(sessionId: string\): Payload =>"),
  ("src/features/belanja/sessionMath.ts", r"export function returnPreview\(items: MathItem\[\]\): \{ count: number \}"),
  ("src/features/belanja/sessionSync.ts", r"export const requestSessionRefresh"),
  ("src/features/belanja/types.ts", r"export interface SessionItemRow"),
  ("src/features/belanja/NoSessionView.tsx", r"export function NoSessionView\(\{ workspaceId, completed \}: \{ workspaceId: string; completed: CompletedView \| null \}\)"),
  ("src/features/belanja/BelanjaView.tsx", r"export function BelanjaView\(\{ workspaceId \}: \{ workspaceId: string \}\)"),
  ("src/features/belanja/ActiveSession.tsx", r"export function ActiveSession\(\{ view, photoUrls \}: \{ view: ActiveView; photoUrls: Record<string, string> \}\)"),
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
  B + "sessionGuardsLive.ts": [
    ("import { countPendingOps } from '../../lib/pending-ops'\n", ""),
    ("export const checkEndLive = () => checkEnd(() => countPendingOps())",
     "// Operasi yang sudah ditolak server tidak dianggap belum tersimpan (SYNC-003), sama seperti saat mulai sesi.\nexport const checkEndLive = () => checkEnd(() => countBlockingOps())"),
  ],
  B + "NoSessionView.tsx": [
    ("import { CompletedSummary } from './CompletedSummary'",
     "import { CompletedSummary } from './CompletedSummary'\nimport { StartSession } from './StartSession'"),
    ("      </section>",
     "        <StartSession\n          workspaceId={workspaceId}\n          summary={readError === null && view !== null ? view.summary : null}\n          catalogPending={catalogPending}\n        />\n      </section>"),
  ],
  B + "ActiveSession.tsx": [
    ("import { SessionItemCard } from './SessionItemCard'",
     "import { SessionActions } from './SessionActions'\nimport { SessionItemCard } from './SessionItemCard'"),
    ("import type { ActiveView } from './sessionView'",
     "import type { ActiveView } from './sessionView'\nimport type { SessionItemRow } from './types'"),
    ("export function ActiveSession({ view, photoUrls }: { view: ActiveView; photoUrls: Record<string, string> }) {",
     "export function ActiveSession({\n  view,\n  photoUrls,\n  workspaceId,\n  sessionId,\n  items,\n}: {\n  view: ActiveView\n  photoUrls: Record<string, string>\n  workspaceId: string\n  sessionId: string\n  items: SessionItemRow[]\n}) {"),
    ("      {view.itemCount === 0 ? (",
     "      <SessionActions workspaceId={workspaceId} sessionId={sessionId} items={items} />\n\n      {view.itemCount === 0 ? ("),
  ],
  B + "BelanjaView.tsx": [
    ("import { NoSessionView } from './NoSessionView'",
     "import { FlowNoticeBanner } from './FlowNoticeBanner'\nimport { NoSessionView } from './NoSessionView'"),
    ("{readError !== null ? (",
     "<FlowNoticeBanner />\n\n      {readError !== null ? ("),
    (") : activeView ? (",
     ") : activeView && state.active ? ("),
    ("<ActiveSession view={activeView} photoUrls={photoUrls} />",
     "<ActiveSession\n              view={activeView}\n              photoUrls={photoUrls}\n              workspaceId={workspaceId}\n              sessionId={state.active.id}\n              items={state.activeItems}\n            />"),
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
cat > "$B/sessionFlow.ts" <<'EOF'
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
EOF

cat > "$B/sessionFlow.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import {
  createSessionFlow,
  endGuard,
  noGuard,
  startGuard,
  type FlowConfig,
  type FlowPhase,
  type GuardOutcome,
  type SettledOutcome,
} from './sessionFlow'

const OK_GUARD: GuardOutcome = { kind: 'ok', note: 'catatan', warning: null }
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

function setup(over: Partial<FlowConfig> = {}, guards: GuardOutcome[] = []) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  const settled: SettledOutcome[] = []
  let guardCalls = 0
  let discards = 0
  let n = 0
  const cfg: FlowConfig = {
    opType: 'kps_start_session',
    payload: () => ({}),
    guard: async () => {
      guardCalls += 1
      return guards.shift() ?? OK_GUARD
    },
    recheckBeforeSend: true,
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    isOnline: () => true,
    newId: () => `op-${++n}`,
    onDiscard: () => {
      discards += 1
    },
    onSettled: (o) => {
      settled.push(o)
    },
    ...over,
  }
  return {
    flow: createSessionFlow(cfg),
    calls,
    results,
    settled,
    guardCalls: () => guardCalls,
    discards: () => discards,
  }
}

describe('mulai sesi: penjaga antrean (FR-045)', () => {
  it('diblokir penjaga: pesan tampil dan RPC tidak pernah dipanggil', async () => {
    const t = setup({}, [{ kind: 'blocked', message: 'Ada 2 perubahan belum tersimpan di server.' }])
    await t.flow.begin()
    const s = t.flow.getState()
    expect(s.phase).toBe('failed')
    expect(s.failure).toMatchObject({ kind: 'guard', message: 'Ada 2 perubahan belum tersimpan di server.' })
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
  })

  it('diizinkan: dialog konfirmasi membawa catatan pengingat, belum ada RPC', async () => {
    const t = setup()
    await t.flow.begin()
    expect(t.flow.getState()).toMatchObject({ phase: 'confirm', note: 'catatan', warning: null })
    expect(t.calls).toHaveLength(0)
  })

  it('antrean diperiksa sekali lagi tepat sebelum kirim', async () => {
    const t = setup()
    await t.flow.begin()
    t.results.push(ok('op-1', { session_id: 's1' }))
    await t.flow.confirm()
    expect(t.guardCalls()).toBe(2)
    expect(t.calls).toHaveLength(1)
    expect(t.flow.getState()).toMatchObject({ phase: 'done', result: { session_id: 's1' } })
  })

  it('antrean berubah di antara dialog dan kirim: diblokir tanpa RPC', async () => {
    const t = setup({}, [OK_GUARD, { kind: 'blocked', message: 'Antrean tidak kosong.' }])
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
    expect(t.flow.getState().failure).toMatchObject({ kind: 'guard', retryable: false })
  })

  it('offline: gagal tanpa memeriksa antrean dan tanpa RPC', async () => {
    const t = setup({ isOnline: () => false })
    await t.flow.begin()
    expect(t.flow.getState().failure).toMatchObject({ kind: 'offline', code: 'OFFLINE' })
    expect(t.guardCalls()).toBe(0)
    expect(t.calls).toHaveLength(0)
  })
})

describe('kunci double-submit', () => {
  it('klik ganda pada konfirmasi hanya mengirim satu RPC', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: async (_type, _payload, o) => {
        sent.push(o.opId)
        return gate
      },
    })
    await t.flow.begin()
    const p1 = t.flow.confirm()
    const p2 = t.flow.confirm()
    const p3 = t.flow.confirm()
    expect(t.flow.getState().phase).toBe('sending')
    release(ok('op-1'))
    await Promise.all([p1, p2, p3])
    expect(sent).toEqual(['op-1'])
    expect(t.flow.getState().phase).toBe('done')
  })

  it('klik ganda pada tombol utama hanya memeriksa penjaga sekali', async () => {
    const t = setup()
    await Promise.all([t.flow.begin(), t.flow.begin()])
    expect(t.guardCalls()).toBe(1)
    expect(t.flow.getState().phase).toBe('confirm')
  })

  it('begin diabaikan selama dialog terbuka dan konfirmasi di luar dialog tidak mengirim apa pun', async () => {
    const t = setup()
    await t.flow.confirm()
    expect(t.calls).toHaveLength(0)
    await t.flow.begin()
    await t.flow.begin()
    expect(t.guardCalls()).toBe(1)
  })
})

describe('kirim ulang dengan op_id yang sama (SYNC-004)', () => {
  it('gagal jaringan menyimpan percobaan; retry memakai op_id dan payload yang sama', async () => {
    const t = setup({ opType: 'kps_end_session', payload: () => ({ session_id: 's1' }), recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1', { returned_items: 2 }))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState()).toMatchObject({ phase: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.flow.hasPending()).toBe(true)

    await t.flow.retry()
    expect(t.flow.getState().phase).toBe('done')
    expect(t.flow.hasPending()).toBe(false)
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.calls[0]).toEqual({ type: 'kps_end_session', payload: { session_id: 's1' }, opId: 'op-1' })
  })

  it('selama percobaan menunggu, begin tidak membuat op_id baru', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('failed')
    expect(t.guardCalls()).toBe(1)
  })

  it('retry yang gagal lagi tetap memakai op_id yang sama', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.retry()
    expect(t.flow.hasPending()).toBe(true)
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('retry diblokir penjaga: percobaan tetap tersimpan dan RPC tidak dikirim lagi', async () => {
    const t = setup({}, [OK_GUARD, OK_GUARD, { kind: 'blocked', message: 'Antrean tidak kosong.' }])
    t.results.push(bad('op-1', 'NETWORK', true))
    await t.flow.begin()
    await t.flow.confirm()
    await t.flow.retry()
    expect(t.calls).toHaveLength(1)
    expect(t.flow.getState().failure).toMatchObject({ kind: 'guard', retryable: true })
    expect(t.flow.hasPending()).toBe(true)
  })

  it('retry tanpa percobaan menunggu tidak melakukan apa pun', async () => {
    const t = setup()
    await t.flow.retry()
    expect(t.calls).toHaveLength(0)
    expect(t.flow.getState().phase).toBe('idle')
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan op_id berikutnya baru', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-2'))
    await t.flow.begin()
    await t.flow.confirm()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.flow.hasPending()).toBe(false)
    expect(t.discards()).toBe(1)

    await t.flow.begin()
    await t.flow.confirm()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })
})

describe('ditolak server berbeda dari gagal jaringan (SYNC-020)', () => {
  it('penolakan: tidak dapat diulang, tercatat sebagai rejected, dan tombol utama boleh dipakai lagi', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'KPS_SESSION_ALREADY_ACTIVE', false), ok('op-2'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().failure).toMatchObject({
      kind: 'rejected',
      code: 'KPS_SESSION_ALREADY_ACTIVE',
      retryable: false,
    })
    expect(t.flow.hasPending()).toBe(false)
    await t.flow.retry()
    expect(t.calls).toHaveLength(1)

    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('confirm')
    expect(t.flow.getState().failure).toBeNull()
    await t.flow.confirm()
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('OFFLINE dan NO_CLIENT dari pengirim dibaca sebagai offline, bukan penolakan server', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'OFFLINE', false))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().failure?.kind).toBe('offline')
  })

  it('hasil akhir dilaporkan sekali per percobaan lewat onSettled', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(bad('op-1', 'KPS_SESSION_NOT_ACTIVE', false))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.settled).toHaveLength(1)
    expect(t.settled[0]).toMatchObject({ ok: false, failure: { kind: 'rejected', code: 'KPS_SESSION_NOT_ACTIVE' } })

    t.results.push(ok('op-2', { item_count: 3 }))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.settled[1]).toEqual({ ok: true, data: { item_count: 3 } })
  })

  it('galat tak terduga tidak membuat alur macet di fase sending', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(new Error('meledak'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('failed')
    expect(t.flow.getState().failure).toMatchObject({ kind: 'unexpected', retryable: false })
    await t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
  })
})

describe('akhiri sesi: konfirmasi kedua (FR-028, SYNC-012)', () => {
  const warn: GuardOutcome = { kind: 'ok', note: '', warning: 'Ada 2 perubahan belum tersimpan di server.' }

  it('dengan peringatan, konfirmasi pertama tidak mengirim; baru konfirmasi kedua mengirim', async () => {
    const t = setup({ opType: 'kps_end_session', payload: () => ({ session_id: 's1' }), recheckBeforeSend: false }, [warn])
    t.results.push(ok('op-1'))
    await t.flow.begin()
    expect(t.flow.getState()).toMatchObject({ phase: 'confirm', warning: 'Ada 2 perubahan belum tersimpan di server.' })
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('confirm_warning')
    expect(t.calls).toHaveLength(0)
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('done')
    expect(t.calls).toHaveLength(1)
    expect(t.guardCalls()).toBe(1)
  })

  it('membatalkan di dialog kedua tidak mengirim apa pun', async () => {
    const t = setup({ recheckBeforeSend: false }, [warn])
    await t.flow.begin()
    await t.flow.confirm()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
  })

  it('tanpa peringatan, satu konfirmasi cukup', async () => {
    const t = setup({ recheckBeforeSend: false })
    t.results.push(ok('op-1'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(t.flow.getState().phase).toBe('done')
  })
})

describe('batalkan sesi tanpa penjaga', () => {
  it('konfirmasi langsung mengirim kps_cancel_session', async () => {
    const t = setup({
      opType: 'kps_cancel_session',
      payload: () => ({ session_id: 's1' }),
      guard: noGuard,
      recheckBeforeSend: false,
    })
    t.results.push(ok('op-1', { returned_items: 4 }))
    await t.flow.begin()
    expect(t.flow.getState().phase).toBe('confirm')
    await t.flow.confirm()
    expect(t.calls).toEqual([{ type: 'kps_cancel_session', payload: { session_id: 's1' }, opId: 'op-1' }])
  })

  it('menutup dialog tidak mengirim apa pun', async () => {
    const t = setup({ guard: noGuard, recheckBeforeSend: false })
    await t.flow.begin()
    t.flow.dismiss()
    expect(t.flow.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
  })
})

describe('perubahan fase terlihat oleh pelanggan', () => {
  it('urutan fase mulai sesi yang berhasil', async () => {
    const t = setup()
    const phases: FlowPhase[] = []
    t.flow.subscribe(() => phases.push(t.flow.getState().phase))
    t.results.push(ok('op-1'))
    await t.flow.begin()
    await t.flow.confirm()
    expect(phases).toEqual(['checking', 'confirm', 'sending', 'done'])
  })
})

describe('adaptor penjaga', () => {
  it('startGuard: diizinkan membawa pengingat, ditolak membawa alasan', async () => {
    expect(await startGuard(async () => ({ allowed: true, message: 'ingat' }))()).toEqual({
      kind: 'ok',
      note: 'ingat',
      warning: null,
    })
    expect(await startGuard(async () => ({ allowed: false, message: 'blokir' }))()).toEqual({
      kind: 'blocked',
      message: 'blokir',
    })
  })

  it('endGuard: tidak pernah memblokir, hanya menambah peringatan bila perlu konfirmasi', async () => {
    expect(await endGuard(async () => ({ needsConfirm: false, message: 'ingat' }))()).toEqual({
      kind: 'ok',
      note: 'ingat',
      warning: null,
    })
    expect(await endGuard(async () => ({ needsConfirm: true, message: 'awas' }))()).toEqual({
      kind: 'ok',
      note: '',
      warning: 'awas',
    })
  })
})
EOF

cat > "$B/flowNotice.ts" <<'EOF'
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
EOF

cat > "$B/flowNotice.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { clearFlowNotice, flowNoticeFor, getFlowNotice, setFlowNotice, subscribeFlowNotice } from './flowNotice'

describe('flowNoticeFor', () => {
  it('penolakan menjadi pesan galat apa adanya', () => {
    expect(flowNoticeFor('end', { ok: false, message: 'Sesi ini sudah selesai.' })).toEqual({
      tone: 'error',
      text: 'Sesi ini sudah selesai.',
    })
  })

  it('mulai: menyebut jumlah barang bila server mengirimnya', () => {
    expect(flowNoticeFor('start', { ok: true, data: { item_count: 3 } }).text).toBe(
      'Sesi belanja dimulai di server dengan 3 barang.',
    )
    expect(flowNoticeFor('start', { ok: true, data: {} }).text).toBe('Sesi belanja dimulai di server.')
  })

  it('akhiri: returned_items sebagai angka atau larik, selain itu teks umum', () => {
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: 2 } }).text).toContain('2 barang dikembalikan')
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: [{}, {}, {}] } }).text).toContain('3 barang dikembalikan')
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: 'x' } }).text).toBe(
      'Sesi belanja diakhiri di server.',
    )
  })

  it('batalkan: semua barang kembali ke daftar', () => {
    const n = flowNoticeFor('cancel', { ok: true, data: {} })
    expect(n.tone).toBe('info')
    expect(n.text).toContain('dibatalkan di server')
  })
})

describe('penyimpanan pesan', () => {
  it('set, baca, beri tahu pelanggan, dan hapus', () => {
    clearFlowNotice()
    let hits = 0
    const off = subscribeFlowNotice(() => {
      hits += 1
    })
    setFlowNotice({ tone: 'info', text: 'a' })
    expect(getFlowNotice()).toEqual({ tone: 'info', text: 'a' })
    clearFlowNotice()
    expect(getFlowNotice()).toBeNull()
    expect(hits).toBe(2)
    off()
    setFlowNotice({ tone: 'error', text: 'b' })
    expect(hits).toBe(2)
    clearFlowNotice()
  })
})
EOF

cat > "$B/flowText.ts" <<'EOF'
import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'

export interface StartFacts {
  itemCount: number
  total: string
  unpricedCount: number
}

// Angka berasal dari data daftar di perangkat ini; server menghitung ulang dan membekukan saat sesi dimulai (FR-024).
export function startDialogMessage(facts: StartFacts, catalogPending: boolean, note: string): string {
  const parts: string[] = []
  if (facts.itemCount === 0) {
    parts.push('Daftar kebutuhan kosong, jadi sesi dimulai tanpa barang.')
  } else {
    parts.push(`${facts.itemCount} barang di daftar kebutuhan akan dipindahkan ke sesi.`)
    parts.push(`Perkiraan estimasi dari harga katalog saat ini: ${formatRupiah(facts.total)}.`)
    if (facts.unpricedCount > 0) parts.push(`${unpricedLabel(facts.unpricedCount)}.`)
    if (catalogPending) parts.push('Katalog belum termuat di perangkat ini, jadi angka ini mungkin belum lengkap.')
    parts.push('Angka ini dari data daftar di perangkat ini. Estimasi awal dibekukan oleh server saat sesi dimulai.')
  }
  if (note) parts.push(note)
  return parts.join(' ')
}

export function endDialogMessage(returnCount: number, note: string): string {
  const parts: string[] = []
  parts.push(
    returnCount > 0
      ? `${returnCount} barang memiliki sisa kebutuhan dan akan dikembalikan ke daftar kebutuhan.`
      : 'Tidak ada barang yang perlu dikembalikan ke daftar.',
  )
  parts.push('Barang yang sudah dibeli sesuai kebutuhan tidak dikembalikan.')
  parts.push('Total aktual dan riwayat dibekukan dari data di server. Hitungan barang di atas dari data di perangkat ini.')
  if (note) parts.push(note)
  return parts.join(' ')
}

export const CANCEL_DIALOG_MESSAGE =
  'Semua barang sesi dikembalikan ke daftar kebutuhan dengan jumlah kebutuhan terakhir. Barang yang ditambahkan langsung ke sesi dan sudah dihapus tidak dikembalikan. Sesi dibatalkan tidak masuk riwayat belanja dan hanya tercatat di log aktivitas. Pembatalan tidak dapat diurungkan.'
EOF

cat > "$B/flowText.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { CANCEL_DIALOG_MESSAGE, endDialogMessage, startDialogMessage } from './flowText'
import { OTHER_DEVICES_REMINDER } from './sessionGuards'

describe('startDialogMessage', () => {
  it('menyebut jumlah barang, estimasi dalam Rupiah, barang tanpa harga, dan pengingat', () => {
    const m = startDialogMessage({ itemCount: 3, total: '15000', unpricedCount: 1 }, false, OTHER_DEVICES_REMINDER)
    expect(m).toContain('3 barang')
    expect(m).toContain('Rp 15.000')
    expect(m).toContain('Belum mencakup 1 barang tanpa harga')
    expect(m).toContain(OTHER_DEVICES_REMINDER)
  })

  it('tidak menyiratkan perangkat lain sudah sinkron (SYNC-013)', () => {
    const m = startDialogMessage({ itemCount: 2, total: '0', unpricedCount: 2 }, false, OTHER_DEVICES_REMINDER)
    expect(m).not.toMatch(/perangkat lain (sudah|telah) (tersinkron|tersimpan|sinkron)/i)
  })

  it('daftar kosong boleh dimulai tanpa angka estimasi (FR-022)', () => {
    const m = startDialogMessage({ itemCount: 0, total: '0', unpricedCount: 0 }, false, '')
    expect(m).toContain('tanpa barang')
    expect(m).not.toContain('Rp')
  })

  it('katalog belum termuat menambah peringatan, barang berharga semua tidak menambah label tanpa harga', () => {
    expect(startDialogMessage({ itemCount: 1, total: '1000', unpricedCount: 0 }, true, '')).toContain('Katalog belum termuat')
    expect(startDialogMessage({ itemCount: 1, total: '1000', unpricedCount: 0 }, false, '')).not.toContain('tanpa harga')
  })
})

describe('endDialogMessage', () => {
  it('pratinjau barang yang kembali, termasuk nol', () => {
    expect(endDialogMessage(2, '')).toContain('2 barang memiliki sisa')
    expect(endDialogMessage(0, '')).toContain('Tidak ada barang yang perlu dikembalikan')
  })

  it('membawa catatan pengingat dan menyebut hitungan dari perangkat ini', () => {
    const m = endDialogMessage(1, OTHER_DEVICES_REMINDER)
    expect(m).toContain(OTHER_DEVICES_REMINDER)
    expect(m).toContain('dari data di perangkat ini')
  })
})

describe('CANCEL_DIALOG_MESSAGE', () => {
  it('memuat konsekuensi FR-029', () => {
    expect(CANCEL_DIALOG_MESSAGE).toContain('dikembalikan ke daftar kebutuhan')
    expect(CANCEL_DIALOG_MESSAGE).toContain('tidak masuk riwayat')
    expect(CANCEL_DIALOG_MESSAGE).toContain('tidak dapat diurungkan')
  })
})
EOF

cat > "$B/sessionGuardsLive.test.ts" <<'EOF'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({ blocking: vi.fn(), pending: vi.fn() }))
vi.mock('../../lib/queue', () => ({ countBlockingOps: mocks.blocking }))
vi.mock('../../lib/pending-ops', () => ({ countPendingOps: mocks.pending }))

import { checkEndLive, checkStartLive } from './sessionGuardsLive'

describe('penjaga langsung memakai countBlockingOps', () => {
  beforeEach(() => {
    mocks.blocking.mockReset()
    mocks.pending.mockReset()
  })

  it('akhir sesi: operasi yang sudah ditolak server (gagal, tidak menghalangi) tidak meminta konfirmasi', async () => {
    mocks.blocking.mockResolvedValue(0)
    mocks.pending.mockResolvedValue(3)
    const plan = await checkEndLive()
    expect(plan.needsConfirm).toBe(false)
    expect(mocks.blocking).toHaveBeenCalledTimes(1)
    expect(mocks.pending).not.toHaveBeenCalled()
  })

  it('akhir sesi: operasi menunggu atau gagal jaringan melewati batas meminta konfirmasi', async () => {
    mocks.blocking.mockResolvedValue(2)
    const plan = await checkEndLive()
    expect(plan.needsConfirm).toBe(true)
    expect(plan.message).toContain('2 perubahan')
  })

  it('mulai dan akhir memakai hitungan yang sama', async () => {
    mocks.blocking.mockResolvedValue(1)
    expect((await checkStartLive()).allowed).toBe(false)
    expect((await checkEndLive()).needsConfirm).toBe(true)
  })

  it('hitungan gagal dibaca dianggap tidak dapat diperiksa', async () => {
    mocks.blocking.mockRejectedValue(new Error('dexie'))
    expect((await checkStartLive()).allowed).toBe(false)
    expect((await checkEndLive()).needsConfirm).toBe(true)
  })
})
EOF

cat > "$B/useSessionFlow.ts" <<'EOF'
import { useMemo, useSyncExternalStore } from 'react'
import { useCallback } from 'react'
import { isOnline } from '../katalog/catalogStore'
import { clearFlowNotice, flowNoticeFor, setFlowNotice } from './flowNotice'
import { createSessionFlow, endGuard, noGuard, startGuard, type FlowAction } from './sessionFlow'
import { checkEndLive, checkStartLive } from './sessionGuardsLive'
import { cancelSessionPayload, endSessionPayload, startSessionPayload } from './sessionPayloads'
import type { SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

const OP: Record<FlowAction, SessionOpType> = {
  start: 'kps_start_session',
  end: 'kps_end_session',
  cancel: 'kps_cancel_session',
}

function requireId(id: string | null): string {
  if (id === null) throw new Error('sessionId diperlukan')
  return id
}

// Menghubungkan pengendali alur murni dengan pengirim sesi yang sudah ada. Tidak ada pola kirim baru.
export function useSessionFlow(workspaceId: string, action: FlowAction, sessionId: string | null) {
  const flow = useMemo(
    () =>
      createSessionFlow({
        opType: OP[action],
        payload: () =>
          action === 'start'
            ? startSessionPayload()
            : action === 'end'
              ? endSessionPayload(requireId(sessionId))
              : cancelSessionPayload(requireId(sessionId)),
        guard: action === 'start' ? startGuard(checkStartLive) : action === 'end' ? endGuard(checkEndLive) : noGuard,
        recheckBeforeSend: action === 'start',
        submit: (type, payload, options) => submitSessionOp(workspaceId, type, payload, options),
        isOnline,
        newId: () => crypto.randomUUID(),
        // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
        onDiscard: requestSessionRefresh,
        // Hanya hasil yang dinilai server yang dibawa ke spanduk halaman, karena layar dapat berpindah.
        onSettled: (o) => {
          if (o.ok) setFlowNotice(flowNoticeFor(action, { ok: true, data: o.data }))
          else if (o.failure.kind === 'rejected') {
            setFlowNotice(flowNoticeFor(action, { ok: false, message: o.failure.message }))
          }
        },
      }),
    [workspaceId, action, sessionId],
  )
  const state = useSyncExternalStore(flow.subscribe, flow.getState, flow.getState)
  const begin = useCallback(() => {
    clearFlowNotice()
    return flow.begin()
  }, [flow])
  return { flow, state, begin }
}
EOF

cat > "$B/FlowNoticeBanner.tsx" <<'EOF'
import { useEffect, useSyncExternalStore } from 'react'
import { clearFlowNotice, getFlowNotice, subscribeFlowNotice } from './flowNotice'

export function FlowNoticeBanner() {
  const notice = useSyncExternalStore(subscribeFlowNotice, getFlowNotice, getFlowNotice)
  // Pesan tidak boleh terbawa ke kunjungan berikutnya atau akun lain.
  useEffect(() => () => clearFlowNotice(), [])
  if (!notice) return null
  const tone = notice.tone === 'error' ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
  return (
    <div
      role={notice.tone === 'error' ? 'alert' : 'status'}
      className={`flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ${tone}`}
    >
      <p className="min-w-0 break-words">{notice.text}</p>
      <button
        type="button"
        className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
        onClick={clearFlowNotice}
      >
        Tutup
      </button>
    </div>
  )
}
EOF

cat > "$B/FlowFailure.tsx" <<'EOF'
import { btnSecondary } from '../../components/ui'
import type { FlowState, SessionFlow } from './sessionFlow'

// Galat lokal alur: diblokir penjaga, offline, jaringan, atau tak terduga. Penolakan server tampil di spanduk halaman.
export function FlowFailure({ flow, state }: { flow: SessionFlow; state: FlowState }) {
  const f = state.failure
  if (state.phase !== 'failed' || f === null || f.kind === 'rejected') return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      <p className="break-words">{f.message}</p>
      {f.retryable ? (
        <>
          <p>
            Belum ada konfirmasi dari server, jadi perubahan ini mungkin sudah atau belum tersimpan. Mengirim ulang aman
            dan tidak menggandakan hasil.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={() => void flow.retry()}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={() => flow.dismiss()}>
              Hentikan percobaan
            </button>
          </div>
          <p className="text-xs">Setelah dihentikan, layar disegarkan dari server untuk melihat hasil sebenarnya.</p>
        </>
      ) : (
        <button type="button" className={btnSecondary} onClick={() => flow.dismiss()}>
          Tutup
        </button>
      )}
    </div>
  )
}
EOF

cat > "$B/StartSession.tsx" <<'EOF'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary } from '../../components/ui'
import { useOnline } from '../daftar/useOnline'
import { FlowFailure } from './FlowFailure'
import { startDialogMessage, type StartFacts } from './flowText'
import { useSessionFlow } from './useSessionFlow'

export function StartSession({
  workspaceId,
  summary,
  catalogPending,
}: {
  workspaceId: string
  summary: StartFacts | null
  catalogPending: boolean
}) {
  const online = useOnline()
  const { flow, state, begin } = useSessionFlow(workspaceId, 'start', null)
  const phase = state.phase
  const holding = phase === 'checking' || phase === 'sending' || phase === 'done'
  const awaitingRetry = phase === 'failed' && state.failure !== null && state.failure.retryable
  const reason = !online
    ? 'Anda sedang offline. Memulai sesi memerlukan koneksi internet.'
    : summary === null
      ? 'Menunggu daftar kebutuhan selesai dibaca dari perangkat.'
      : null
  const label = phase === 'checking' ? 'Memeriksa...' : phase === 'sending' ? 'Memulai...' : 'Mulai sesi belanja'

  return (
    <div className="space-y-3">
      <button
        type="button"
        className={btnPrimary}
        onClick={() => void begin()}
        disabled={reason !== null || holding || awaitingRetry}
      >
        {label}
      </button>
      {reason ? <p className="text-sm">{reason}</p> : null}
      <FlowFailure flow={flow} state={state} />
      <ConfirmDialog
        open={phase === 'confirm'}
        title="Mulai sesi belanja?"
        message={summary ? startDialogMessage(summary, catalogPending, state.note) : ''}
        confirmLabel="Mulai sesi"
        cancelLabel="Kembali"
        onConfirm={() => void flow.confirm()}
        onCancel={() => flow.dismiss()}
      />
    </div>
  )
}
EOF

cat > "$B/SessionActions.tsx" <<'EOF'
import { useMemo } from 'react'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { useOnline } from '../daftar/useOnline'
import { FlowFailure } from './FlowFailure'
import { CANCEL_DIALOG_MESSAGE, endDialogMessage } from './flowText'
import type { FlowState } from './sessionFlow'
import { returnPreview } from './sessionMath'
import type { SessionItemRow } from './types'
import { useSessionFlow } from './useSessionFlow'

const holds = (s: FlowState) => s.phase === 'checking' || s.phase === 'sending' || s.phase === 'done'
const awaitsRetry = (s: FlowState) => s.phase === 'failed' && s.failure !== null && s.failure.retryable

export function SessionActions({
  workspaceId,
  sessionId,
  items,
}: {
  workspaceId: string
  sessionId: string
  items: SessionItemRow[]
}) {
  const online = useOnline()
  const end = useSessionFlow(workspaceId, 'end', sessionId)
  const cancel = useSessionFlow(workspaceId, 'cancel', sessionId)
  const returning = useMemo(() => returnPreview(items).count, [items])

  const locked = holds(end.state) || holds(cancel.state) || awaitsRetry(end.state) || awaitsRetry(cancel.state)
  const endLabel =
    end.state.phase === 'checking' ? 'Memeriksa...' : end.state.phase === 'sending' ? 'Mengakhiri...' : 'Akhiri sesi'
  const cancelLabel = cancel.state.phase === 'sending' ? 'Membatalkan...' : 'Batalkan sesi'

  return (
    <section aria-labelledby="kelola-sesi" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="kelola-sesi" className="font-semibold">
        Kelola sesi
      </h2>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className={btnPrimary}
          onClick={() => void end.begin()}
          disabled={locked || !online}
        >
          {endLabel}
        </button>
        <button
          type="button"
          className={btnSecondary}
          onClick={() => void cancel.begin()}
          disabled={locked || !online}
        >
          {cancelLabel}
        </button>
      </div>
      {!online ? (
        <p className="text-sm">Anda sedang offline. Mengakhiri atau membatalkan sesi memerlukan koneksi internet.</p>
      ) : null}
      <FlowFailure flow={end.flow} state={end.state} />
      <FlowFailure flow={cancel.flow} state={cancel.state} />

      <ConfirmDialog
        open={end.state.phase === 'confirm'}
        title="Akhiri sesi belanja?"
        message={endDialogMessage(returning, end.state.note)}
        confirmLabel="Akhiri sesi"
        cancelLabel="Kembali"
        onConfirm={() => void end.flow.confirm()}
        onCancel={() => end.flow.dismiss()}
      />
      <ConfirmDialog
        open={end.state.phase === 'confirm_warning'}
        title="Ada perubahan yang belum tersimpan"
        message={end.state.warning ?? ''}
        confirmLabel="Tetap akhiri sesi"
        cancelLabel="Kembali"
        onConfirm={() => void end.flow.confirm()}
        onCancel={() => end.flow.dismiss()}
      />
      <ConfirmDialog
        open={cancel.state.phase === 'confirm'}
        title="Batalkan sesi belanja?"
        message={CANCEL_DIALOG_MESSAGE}
        confirmLabel="Ya, batalkan sesi"
        cancelLabel="Kembali ke sesi"
        onConfirm={() => void cancel.flow.confirm()}
        onCancel={() => cancel.flow.dismiss()}
      />
    </section>
  )
}
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run && npm run build"
