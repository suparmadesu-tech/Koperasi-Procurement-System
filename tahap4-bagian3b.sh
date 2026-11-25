#!/usr/bin/env bash
# KPS Tahap 4, Bagian 3B: checklist, jumlah aktual, harga aktual, aksi massal.
# Tambah barang ke sesi, ubah jumlah kebutuhan, hapus barang langsung, dan foto bukan bagian ini (3C).
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

for f in src/components/ConfirmDialog.tsx src/components/ui.ts src/lib/money.ts \
  src/features/katalog/moneyAdapter.ts src/features/katalog/catalogStore.ts \
  "$D/attemptRunner.ts" "$D/submitCore.ts" "$D/types.ts" "$D/useOnline.ts" "$D/TextField.tsx" "$D/format.ts" \
  "$B/ActiveSession.tsx" "$B/SessionItemCard.tsx" "$B/sessionView.ts" "$B/sessionPayloads.ts" \
  "$B/sessionValidation.ts" "$B/sessionErrors.ts" "$B/sessionRpc.ts" "$B/sessionSync.ts" \
  "$B/submitSessionOp.ts" "$B/types.ts" "$B/sessionMath.ts"; do
  [ -f "$f" ] || fail "berkas tidak ada: $f"
done
for f in itemOps.ts itemOps.test.ts bulkBatch.ts bulkBatch.test.ts checklistForms.ts checklistForms.test.ts \
  sessionView3b.test.ts useChecklist.ts ChecklistStatus.tsx EditableSessionItemCard.tsx BulkPurchase.tsx; do
  [ ! -e "$B/$f" ] || fail "$B/$f sudah ada; tidak ditimpa"
done
! grep -qF 'allowFraction' "$B/sessionView.ts" || fail "$B/sessionView.ts sudah memuat allowFraction"
! grep -qF 'children' "$B/SessionItemCard.tsx" || fail "$B/SessionItemCard.tsx sudah memuat children"
! grep -qF 'useChecklist' "$B/ActiveSession.tsx" || fail "$B/ActiveSession.tsx sudah memuat useChecklist"
! grep -qF 'useId' src/components/ConfirmDialog.tsx || fail "ConfirmDialog.tsx sudah memuat useId"

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
  ("src/features/daftar/format.ts", r"export function formatQuantity\(q: string\): string"),
  ("src/features/daftar/TextField.tsx", r"export function TextField\(\{[^}]*\}: \{\s*id: string\s*label: string\s*value: string\s*onChange: \(v: string\) => void\s*error\?: string \| undefined\s*hint\?: string \| undefined\s*inputMode\?: 'text' \| 'decimal' \| 'numeric' \| undefined\s*multiline\?: boolean \| undefined\s*readOnly\?: boolean \| undefined"),
  ("src/features/katalog/catalogStore.ts", r"export const isOnline"),
  ("src/features/katalog/moneyAdapter.ts", r"export type PriceParse = \{ ok: true; value: string \| null \} \| \{ ok: false; message: string \}"),
  ("src/features/katalog/moneyAdapter.ts", r"export function parsePriceInput\(raw: string\): PriceParse"),
  ("src/lib/money.ts", r"export function formatRupiah\(v: string \| number \| Decimal\): string"),
  ("src/components/ui.ts", r"export const btnPrimary"),
  ("src/components/ui.ts", r"export const btnSecondary"),
  ("src/components/ConfirmDialog.tsx", r"export default function ConfirmDialog\(props: Props\)"),
  ("src/components/ConfirmDialog.tsx", r"open: boolean;\s*title: string;\s*message: string;\s*confirmLabel: string;\s*cancelLabel: string;\s*onConfirm: \(\) => void;\s*onCancel: \(\) => void;"),
  ("src/features/belanja/submitSessionOp.ts", r"export function submitSessionOp\(\s*workspaceId: string,\s*opType: SessionOpType,\s*payload: Record<string, unknown>,\s*options: SubmitOptions = \{\},?\s*\): Promise<SessionOpResult>"),
  ("src/features/belanja/sessionRpc.ts", r"export type ApplyOp\s*=\s*\|\s*'session_add_manual'\s*\|\s*'session_set_status'\s*\|\s*'session_set_quantity_actual'\s*\|\s*'session_set_price_actual'"),
  ("src/features/belanja/sessionRpc.ts", r"export type SessionOpType = DirectOp \| ApplyOp"),
  ("src/features/belanja/sessionSync.ts", r"export const requestSessionRefresh"),
  ("src/features/belanja/sessionPayloads.ts", r"export const setStatusPayload = \(itemId: string, status: ItemStatus\): Payload =>"),
  ("src/features/belanja/sessionPayloads.ts", r"export const setQuantityActualPayload = \(itemId: string, quantity: string\): Payload =>"),
  ("src/features/belanja/sessionPayloads.ts", r"export const setPriceActualPayload = \(itemId: string, price: string \| null\): Payload =>"),
  ("src/features/belanja/sessionValidation.ts", r"export function parseActualQuantityInput\(text: string, opts: \{ allowFraction: boolean \}\): QuantityResult"),
  ("src/features/belanja/sessionValidation.ts", r"export \{ parsePriceInput as parsePriceActualInput \} from '\.\./katalog/moneyAdapter'"),
  ("src/features/belanja/sessionView.ts", r"export const STATUS_LABEL: Record<ItemStatus, string>"),
  ("src/features/belanja/sessionView.ts", r"export interface SessionItemView \{[^}]*priceIsActual: boolean[^}]*direct: boolean\s*\}"),
  ("src/features/belanja/sessionMath.ts", r"export function runningTotals\(items: MathItem\[\]\): Totals"),
  ("src/features/belanja/types.ts", r"export const ITEM_STATUSES: readonly ItemStatus\[\]"),
  ("src/features/belanja/ActiveSession.tsx", r"export function ActiveSession\(\{\s*view,\s*photoUrls,\s*workspaceId,\s*sessionId,\s*items,\s*\}: \{\s*view: ActiveView\s*photoUrls: Record<string, string>\s*workspaceId: string\s*sessionId: string\s*items: SessionItemRow\[\]\s*\}\)"),
  ("src/features/belanja/SessionItemCard.tsx", r"export function SessionItemCard\(\{ item, photoUrl \}: \{ item: SessionItemView; photoUrl: string \| undefined \}\)"),
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
  B + "sessionView.ts": [
    ("  direct: boolean",
     "  direct: boolean\n  // allow_fraction_snapshot: pecahan jumlah aktual mengikuti snapshot (FR-012).\n  allowFraction: boolean"),
    ("    direct: i.source_item_id === null,",
     "    direct: i.source_item_id === null,\n    allowFraction: i.allow_fraction_snapshot,"),
  ],
  B + "SessionItemCard.tsx": [
    ("import { formatRupiah } from '../../lib/money'",
     "import type { ReactNode } from 'react'\nimport { formatRupiah } from '../../lib/money'"),
    ("export function SessionItemCard({ item, photoUrl }: { item: SessionItemView; photoUrl: string | undefined }) {",
     "export function SessionItemCard({\n  item,\n  photoUrl,\n  children,\n}: {\n  item: SessionItemView\n  photoUrl: string | undefined\n  children?: ReactNode\n}) {"),
    ('        {item.direct ? <p className="text-xs text-ink/75">Ditambahkan langsung ke sesi</p> : null}',
     '        {item.direct ? <p className="text-xs text-ink/75">Ditambahkan langsung ke sesi</p> : null}\n        {children}'),
  ],
  B + "ActiveSession.tsx": [
    ("import { unpricedLabel } from '../daftar/listView'",
     "import { unpricedLabel } from '../daftar/listView'\nimport { useOnline } from '../daftar/useOnline'"),
    ("import { SessionItemCard } from './SessionItemCard'",
     "import { BulkPurchase } from './BulkPurchase'\nimport { ChecklistStatus } from './ChecklistStatus'\nimport { EditableSessionItemCard } from './EditableSessionItemCard'"),
    ("import type { SessionItemRow } from './types'",
     "import type { SessionItemRow } from './types'\nimport { useChecklist } from './useChecklist'"),
    ("  const { running, frozen } = view",
     "  const online = useOnline()\n  const checklist = useChecklist(workspaceId)\n  const inCart = (view.groups.find((g) => g.status === 'in_cart')?.items ?? []).map((i) => ({\n    id: i.id,\n    name: i.name,\n  }))\n  const { running, frozen } = view"),
    ("      <SessionActions workspaceId={workspaceId} sessionId={sessionId} items={items} />",
     "      <SessionActions workspaceId={workspaceId} sessionId={sessionId} items={items} />\n\n      <ChecklistStatus checklist={checklist} online={online} />\n\n      <BulkPurchase checklist={checklist} items={inCart} online={online} />"),
    ("                <SessionItemCard key={i.id} item={i} photoUrl={i.photoPath ? photoUrls[i.photoPath] : undefined} />",
     "                <EditableSessionItemCard\n                  key={i.id}\n                  item={i}\n                  photoUrl={i.photoPath ? photoUrls[i.photoPath] : undefined}\n                  checklist={checklist}\n                  online={online}\n                />"),
  ],
  # id judul dialog harus unik: beberapa dialog hidup bersamaan di halaman yang sama.
  "src/components/ConfirmDialog.tsx": [
    ("import { useEffect, useRef } from 'react';",
     "import { useEffect, useId, useRef } from 'react';"),
    ("  const ref = useRef<HTMLDialogElement>(null);",
     "  const ref = useRef<HTMLDialogElement>(null);\n  const titleId = useId();"),
    ('      aria-labelledby="confirm-title"',
     "      aria-labelledby={titleId}"),
    ('      <h2 id="confirm-title" className="text-lg font-semibold">',
     '      <h2 id={titleId} className="text-lg font-semibold">'),
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
cat > "$B/itemOps.ts" <<'EOF'
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
EOF

cat > "$B/itemOps.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import { createItemOps, type ItemOpsConfig } from './itemOps'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})

function setup(over: Partial<ItemOpsConfig> = {}) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  const results: Array<ListOpResult | Error> = []
  let discards = 0
  let n = 0
  const ops = createItemOps({
    submit: async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      if (r instanceof Error) throw r
      return r
    },
    newId: () => `op-${++n}`,
    isOnline: () => true,
    onDiscard: () => {
      discards += 1
    },
    ...over,
  })
  return { ops, calls, results, discards: () => discards }
}

const P = { item_id: 'a', status: 'in_cart' }

describe('kunci per barang', () => {
  it('sukses: satu pengiriman, kembali idle, dan hasil dikonfirmasi tercatat', async () => {
    const t = setup()
    t.results.push(ok('op-1'))
    const out = await t.ops.run('a', 'session_set_status', P, 'Beras: status diubah.')
    expect(out).toEqual({ status: 'ok' })
    expect(t.ops.getItem('a')).toEqual({ phase: 'idle', failure: null })
    expect(t.ops.getLast()).toEqual({ seq: 1, text: 'Beras: status diubah.' })
    expect(t.calls).toEqual([{ type: 'session_set_status', payload: P, opId: 'op-1' }])
  })

  it('klik ganda pada barang yang sama hanya mengirim sekali', async () => {
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
    const p1 = t.ops.run('a', 'session_set_status', P, 'x')
    const p2 = t.ops.run('a', 'session_set_status', P, 'x')
    const p3 = t.ops.run('a', 'session_set_quantity_actual', { item_id: 'a', quantity: 2 }, 'y')
    expect(t.ops.getItem('a').phase).toBe('sending')
    release(ok('op-1'))
    expect(await Promise.all([p1, p2, p3])).toEqual([{ status: 'ok' }, { status: 'ignored' }, { status: 'ignored' }])
    expect(sent).toEqual(['op-1'])
  })

  it('barang berbeda tidak saling mengunci dan memakai op_id berbeda', async () => {
    const gates: Array<(r: ListOpResult) => void> = []
    const sent: Array<string | undefined> = []
    const t = setup({
      submit: (_t, _p, o) =>
        new Promise<ListOpResult>((res) => {
          sent.push(o.opId)
          gates.push(res)
        }),
    })
    const pa = t.ops.run('a', 'session_set_status', { item_id: 'a', status: 'purchased' }, 'a')
    const pb = t.ops.run('b', 'session_set_status', { item_id: 'b', status: 'purchased' }, 'b')
    expect(t.ops.getItem('a').phase).toBe('sending')
    expect(t.ops.getItem('b').phase).toBe('sending')
    expect(sent).toEqual(['op-1', 'op-2'])
    gates.forEach((g, i) => g(ok(`op-${i + 1}`)))
    await Promise.all([pa, pb])
    expect(t.ops.anyBusy()).toBe(false)
  })
})

describe('ditolak server berbeda dari gagal jaringan (SYNC-020)', () => {
  it('penolakan: tidak dapat diulang, dapat ditutup, dan niat baru memakai op_id baru', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'KPS_ITEM_DELETED', false), ok('op-2'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'rejected', code: 'KPS_ITEM_DELETED', retryable: false } })
    expect(t.ops.anyBusy()).toBe(false)
    expect(await t.ops.retry('a')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)

    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
    expect(t.ops.getItem('a').failure).toBeNull()
    expect(t.discards()).toBe(0)

    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('jaringan gagal: percobaan menunggu, niat baru diabaikan, retry memakai op_id dan payload lama', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'network', retryable: true } })
    expect(t.ops.anyBusy()).toBe(true)

    expect(await t.ops.run('a', 'session_set_status', { item_id: 'a', status: 'purchased' }, 'z')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)

    expect(await t.ops.retry('a')).toEqual({ status: 'ok' })
    expect(t.calls).toHaveLength(2)
    expect(t.calls[1]).toEqual(t.calls[0])
    expect(t.ops.anyBusy()).toBe(false)
    expect(t.ops.getLast()?.text).toBe('x')
  })

  it('menghentikan percobaan membuangnya, menyegarkan layar, dan op_id berikutnya baru', async () => {
    const t = setup()
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-2'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
    expect(t.discards()).toBe(1)
    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('retry saat offline tidak memanggil pengirim dan percobaan tetap tersimpan', async () => {
    let online = true
    const t = setup({ isOnline: () => online })
    t.results.push(bad('op-1', 'NETWORK', true), ok('op-1'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    online = false
    expect(await t.ops.retry('a')).toEqual({ status: 'ignored' })
    expect(t.calls).toHaveLength(1)
    expect(t.ops.getItem('a').phase).toBe('failed')
    online = true
    expect(await t.ops.retry('a')).toEqual({ status: 'ok' })
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-1'])
  })

  it('offline saat niat baru: gagal tanpa mengirim apa pun', async () => {
    const t = setup({ isOnline: () => false })
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'offline', code: 'OFFLINE', retryable: false } })
    expect(t.calls).toHaveLength(0)
  })

  it('galat tak terduga tidak membuat slot macet di fase sending', async () => {
    const t = setup()
    t.results.push(new Error('meledak'))
    const out = await t.ops.run('a', 'session_set_status', P, 'x')
    expect(out).toMatchObject({ status: 'failed', failure: { kind: 'unexpected', retryable: false } })
    expect(t.ops.getItem('a').phase).toBe('failed')
    t.ops.dismiss('a')
    expect(t.ops.getItem('a').phase).toBe('idle')
  })
})

describe('keadaan untuk pelanggan', () => {
  it('getItem stabil selama tidak berubah dan pelanggan diberi tahu saat berubah', async () => {
    const t = setup()
    expect(t.ops.getItem('x')).toBe(t.ops.getItem('x'))
    let hits = 0
    const off = t.ops.subscribe(() => {
      hits += 1
    })
    t.results.push(ok('op-1'))
    await t.ops.run('a', 'session_set_status', P, 'x')
    expect(hits).toBe(2)
    expect(t.ops.getItem('a')).toBe(t.ops.getItem('a'))
    off()
  })

  it('urutan hasil dikonfirmasi bertambah per sukses', async () => {
    const t = setup()
    t.results.push(ok('op-1'), ok('op-2'))
    await t.ops.run('a', 'session_set_status', P, 'satu')
    await t.ops.run('b', 'session_set_status', P, 'dua')
    expect(t.ops.getLast()).toEqual({ seq: 2, text: 'dua' })
  })
})
EOF

cat > "$B/bulkBatch.ts" <<'EOF'
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
EOF

cat > "$B/bulkBatch.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { ListOpResult } from '../daftar/types'
import { buildBulkReport, bulkConfirmMessage, bulkSummaryLine, createBulkBatch, type BulkConfig } from './bulkBatch'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, code: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code,
  message: `pesan ${code}`,
  retryable,
})
const ITEMS = [
  { id: 'a', name: 'Apel' },
  { id: 'b', name: 'Beras' },
  { id: 'c', name: 'Cabai' },
]

// script: hasil per barang berurutan; barang tanpa script dianggap sukses.
function setup(script: Record<string, Array<ListOpResult | Error>> = {}, over: Partial<BulkConfig> = {}) {
  const calls: Array<{ itemId: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  let discards = 0
  let n = 0
  const batch = createBulkBatch({
    submit: async (_type, payload, options) => {
      const itemId = String(payload.item_id)
      calls.push({ itemId, payload, opId: options.opId })
      const next = script[itemId]?.shift()
      if (next instanceof Error) throw next
      return next ?? ok(options.opId ?? '')
    },
    newId: () => `op-${++n}`,
    isOnline: () => true,
    onDiscard: () => {
      discards += 1
    },
    ...over,
  })
  return { batch, calls, discards: () => discards }
}

async function start(t: ReturnType<typeof setup>, items = ITEMS) {
  t.batch.open(items)
  await t.batch.confirm()
}

describe('urutan dan op_id per barang', () => {
  it('semua berhasil: satu session_set_status per barang, berurutan, op_id berbeda', async () => {
    const t = setup()
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'c'])
    expect(new Set(t.calls.map((c) => c.opId)).size).toBe(3)
    expect(t.calls.every((c) => c.payload.status === 'purchased')).toBe(true)
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    expect(buildBulkReport(s)).toMatchObject({ total: 3, ok: 3, unprocessed: 0, uncertain: false, rejected: [] })
  })

  it('dialog konfirmasi menyebut jumlah barang dan belum mengirim apa pun', () => {
    const t = setup()
    t.batch.open(ITEMS)
    expect(t.batch.getState().phase).toBe('confirm')
    expect(t.batch.getState().entries).toHaveLength(3)
    expect(t.calls).toHaveLength(0)
    expect(bulkConfirmMessage(3)).toContain('3 barang di keranjang')
  })
})

describe('penolakan tidak menghentikan batch (SYNC-003)', () => {
  it('batch lanjut setelah satu barang ditolak, dan laporan menyebut nama dan alasan', async () => {
    const t = setup({ b: [bad('x', 'KPS_ITEM_DELETED', false)] })
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'c'])
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    const r = buildBulkReport(s)
    expect(r.ok).toBe(2)
    expect(r.unprocessed).toBe(0)
    expect(r.rejected).toEqual([{ id: 'b', name: 'Beras', code: 'KPS_ITEM_DELETED', message: 'pesan KPS_ITEM_DELETED' }])
    expect(bulkSummaryLine(r)).toBe('2 berhasil di server, 1 ditolak, 0 belum diproses.')
  })

  it('semua ditolak: batch tetap selesai dan melaporkan semuanya', async () => {
    const rej = () => [bad('x', 'KPS_SESSION_NOT_ACTIVE', false)]
    const t = setup({ a: rej(), b: rej(), c: rej() })
    await start(t)
    expect(t.calls).toHaveLength(3)
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 0, unprocessed: 0 })
    expect(buildBulkReport(t.batch.getState()).rejected).toHaveLength(3)
  })
})

describe('jaringan gagal menghentikan batch dan retry memakai op_id lama (SYNC-004)', () => {
  it('berhenti pada barang yang gagal; sisanya belum diproses; barang itu belum pasti', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b'])
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('network')
    const r = buildBulkReport(s)
    expect(r).toMatchObject({ ok: 1, unprocessed: 2, uncertain: true })
    expect(bulkSummaryLine(r)).toContain('1 berhasil di server, 0 ditolak, 2 belum diproses.')
    expect(bulkSummaryLine(r)).toContain('mungkin sudah tersimpan')
  })

  it('retry mengirim ulang barang yang gagal dengan op_id yang sama, lalu melanjutkan sisanya tanpa pengiriman ganda', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    await t.batch.retry()
    expect(t.calls.map((c) => `${c.itemId}:${c.opId}`)).toEqual(['a:op-1', 'b:op-2', 'b:op-2', 'c:op-3'])
    expect(t.batch.getState().phase).toBe('done')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 3, unprocessed: 0, uncertain: false })
  })

  it('retry yang gagal lagi tetap memakai op_id yang sama', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true), bad('x', 'NETWORK', true)] })
    await start(t)
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('halted')
    expect(t.calls.filter((c) => c.itemId === 'b').map((c) => c.opId)).toEqual(['op-2', 'op-2'])
  })

  it('penolakan setelah retry tetap tercatat dan batch lanjut', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true), bad('x', 'KPS_ITEM_DELETED', false)] })
    await start(t)
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('done')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 2, unprocessed: 0 })
    expect(t.calls.map((c) => c.itemId)).toEqual(['a', 'b', 'b', 'c'])
  })

  it('menghentikan batch: sisa tidak diproses, layar disegarkan, dan laporan tetap jujur', async () => {
    const t = setup({ b: [bad('x', 'NETWORK', true)] })
    await start(t)
    t.batch.discard()
    const s = t.batch.getState()
    expect(s.phase).toBe('done')
    expect(s.discarded).toBe(true)
    expect(t.discards()).toBe(1)
    expect(buildBulkReport(s)).toMatchObject({ ok: 1, unprocessed: 2, uncertain: true, discarded: true })
    expect(t.calls).toHaveLength(2)
  })
})

describe('offline, sesi berakhir, dan galat tak terduga', () => {
  it('offline di tengah batch: berhenti sebelum mengirim barang berikutnya, retry diabaikan sampai online', async () => {
    let online = true
    const t = setup({}, {
      isOnline: () => online,
      submit: async (_t, payload, options) => {
        if (payload.item_id === 'a') online = false
        return ok(options.opId ?? '')
      },
    })
    await start(t)
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('offline')
    expect(buildBulkReport(s)).toMatchObject({ ok: 1, unprocessed: 2, uncertain: false })

    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('halted')
    online = true
    await t.batch.retry()
    expect(t.batch.getState().phase).toBe('done')
  })

  it('SESSION_EXPIRED menghentikan batch, bukan menolak tiap barang', async () => {
    const t = setup({ a: [bad('x', 'SESSION_EXPIRED', false)] })
    await start(t)
    const s = t.batch.getState()
    expect(s.phase).toBe('halted')
    expect(s.halt?.kind).toBe('session')
    expect(t.calls).toHaveLength(1)
    expect(buildBulkReport(s)).toMatchObject({ ok: 0, unprocessed: 3, uncertain: false })
  })

  it('galat tak terduga tidak membuat batch macet di fase running', async () => {
    const t = setup({ b: [new Error('meledak')] })
    await start(t)
    expect(t.batch.getState().phase).toBe('halted')
    expect(t.batch.getState().halt?.kind).toBe('unexpected')
    expect(buildBulkReport(t.batch.getState())).toMatchObject({ ok: 1, unprocessed: 2 })
  })
})

describe('kunci dan siklus', () => {
  it('konfirmasi berganda hanya menjalankan satu batch', async () => {
    let release!: (r: ListOpResult) => void
    const gate = new Promise<ListOpResult>((res) => {
      release = res
    })
    const sent: string[] = []
    const t = setup({}, {
      submit: async (_t, payload, options) => {
        sent.push(String(payload.item_id))
        return payload.item_id === 'a' ? gate : ok(options.opId ?? '')
      },
    })
    t.batch.open(ITEMS)
    const p1 = t.batch.confirm()
    const p2 = t.batch.confirm()
    const p3 = t.batch.confirm()
    expect(t.batch.getState().phase).toBe('running')
    release(ok('op-1'))
    await Promise.all([p1, p2, p3])
    expect(sent).toEqual(['a', 'b', 'c'])
  })

  it('open diabaikan saat berjalan atau tertahan, kosong, atau offline', async () => {
    const t = setup({ a: [bad('x', 'NETWORK', true)] })
    t.batch.open([])
    expect(t.batch.getState().phase).toBe('idle')
    await start(t)
    t.batch.open(ITEMS)
    expect(t.batch.getState().phase).toBe('halted')
    const off = setup({}, { isOnline: () => false })
    off.batch.open(ITEMS)
    expect(off.batch.getState().phase).toBe('idle')
  })

  it('membatalkan di dialog tidak mengirim apa pun; tidak dapat dibatalkan saat berjalan', async () => {
    const t = setup()
    t.batch.open(ITEMS)
    t.batch.cancel()
    expect(t.batch.getState().phase).toBe('idle')
    expect(t.calls).toHaveLength(0)
    await t.batch.confirm()
    expect(t.calls).toHaveLength(0)
  })

  it('selesai lalu ditutup; batch baru memakai op_id baru', async () => {
    const t = setup()
    await start(t, [ITEMS[0]!])
    t.batch.close()
    expect(t.batch.getState().phase).toBe('idle')
    await start(t, [ITEMS[1]!])
    expect(t.calls.map((c) => c.opId)).toEqual(['op-1', 'op-2'])
  })

  it('pelanggan diberi tahu pada tiap perubahan dan getState stabil', async () => {
    const t = setup()
    let hits = 0
    t.batch.subscribe(() => {
      hits += 1
    })
    await start(t, [ITEMS[0]!])
    expect(hits).toBeGreaterThanOrEqual(3)
    expect(t.batch.getState()).toBe(t.batch.getState())
  })
})
EOF

cat > "$B/checklistForms.ts" <<'EOF'
import { formatRupiah } from '../../lib/money'
import { formatQuantity } from '../daftar/format'
import { parseActualQuantityInput, parsePriceActualInput } from './sessionValidation'
import { STATUS_LABEL, type SessionItemView } from './sessionView'
import type { ItemStatus } from './types'

type QuantityItem = Pick<SessionItemView, 'status' | 'actual' | 'allowFraction'>
type PriceItem = Pick<SessionItemView, 'price' | 'priceIsActual'>

export type QuantityPlan = { kind: 'invalid'; message: string } | { kind: 'noop' } | { kind: 'send'; value: string }
export type PricePlan = { kind: 'invalid'; message: string } | { kind: 'noop' } | { kind: 'send'; value: string | null }

export const actualQuantityPrefill = (item: Pick<SessionItemView, 'actual'>): string =>
  item.actual === null ? '' : item.actual.replace('.', ',')

// Hanya harga aktual yang diisi ulang; harga awal sesi bukan nilai yang diubah pengguna (FR-053).
export const priceActualPrefill = (item: PriceItem): string =>
  item.priceIsActual && item.price !== null ? item.price : ''

// Jumlah aktual diisi hanya untuk in_cart atau purchased; server tetap penentu (KPS_QUANTITY_ACTUAL_STATE).
export function planActualQuantity(item: QuantityItem, text: string): QuantityPlan {
  if (item.status === 'to_buy') {
    return { kind: 'invalid', message: 'Jumlah aktual hanya dapat diisi untuk barang di keranjang atau sudah dibeli.' }
  }
  const q = parseActualQuantityInput(text, { allowFraction: item.allowFraction })
  if (!q.ok) return { kind: 'invalid', message: q.message }
  return q.value === item.actual ? { kind: 'noop' } : { kind: 'send', value: q.value }
}

// Kosong berarti mengosongkan (kirim null); 0 sah (FR-053).
export function planPriceActual(item: PriceItem, text: string): PricePlan {
  const p = parsePriceActualInput(text)
  if (!p.ok) return { kind: 'invalid', message: p.message }
  const current = item.priceIsActual ? item.price : null
  return p.value === current ? { kind: 'noop' } : { kind: 'send', value: p.value }
}

// Teks dipakai hanya setelah jawaban server diterima (SYNC-006).
export const statusOkText = (name: string, status: ItemStatus): string =>
  `${name}: status diubah menjadi ${STATUS_LABEL[status]} (dikonfirmasi server).`

export const quantityOkText = (name: string, value: string, unit: string): string =>
  `Jumlah aktual ${name} menjadi ${formatQuantity(value)}${unit ? ` ${unit}` : ''} (dikonfirmasi server).`

export const priceOkText = (name: string, value: string | null): string =>
  value === null
    ? `Harga aktual ${name} dikosongkan; memakai harga awal sesi (dikonfirmasi server).`
    : `Harga aktual ${name} menjadi ${formatRupiah(value)} (dikonfirmasi server).`
EOF

cat > "$B/checklistForms.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import {
  actualQuantityPrefill,
  planActualQuantity,
  planPriceActual,
  priceActualPrefill,
  priceOkText,
  quantityOkText,
  statusOkText,
} from './checklistForms'

const cart = { status: 'in_cart' as const, actual: '2', allowFraction: true }

describe('planActualQuantity (FR-032)', () => {
  it('to_buy ditolak di klien dengan alasan yang jelas, tanpa mengirim', () => {
    const p = planActualQuantity({ status: 'to_buy', actual: null, allowFraction: true }, '2')
    expect(p).toMatchObject({ kind: 'invalid' })
  })

  it('0 diterima, koma desimal, dan maksimal 3 desimal', () => {
    expect(planActualQuantity(cart, '0')).toEqual({ kind: 'send', value: '0' })
    expect(planActualQuantity(cart, '1,5')).toEqual({ kind: 'send', value: '1.5' })
    expect(planActualQuantity(cart, '0,0001')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity(cart, '')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity(cart, '-1')).toMatchObject({ kind: 'invalid' })
  })

  it('pecahan mengikuti allow_fraction_snapshot', () => {
    expect(planActualQuantity({ ...cart, allowFraction: false }, '0,5')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity({ ...cart, allowFraction: false }, '3')).toEqual({ kind: 'send', value: '3' })
  })

  it('nilai yang sama tidak dikirim', () => {
    expect(planActualQuantity(cart, '2')).toEqual({ kind: 'noop' })
    expect(planActualQuantity(cart, '2,0')).toEqual({ kind: 'noop' })
  })
})

describe('planPriceActual (FR-053)', () => {
  const noActual = { price: '10000', priceIsActual: false }
  const withActual = { price: '11000', priceIsActual: true }

  it('kosong mengosongkan hanya bila harga aktual terisi', () => {
    expect(planPriceActual(withActual, '')).toEqual({ kind: 'send', value: null })
    expect(planPriceActual(noActual, '')).toEqual({ kind: 'noop' })
    expect(planPriceActual({ price: null, priceIsActual: false }, '  ')).toEqual({ kind: 'noop' })
  })

  it('0 sah dan dikirim sebagai harga, bukan dianggap kosong', () => {
    expect(planPriceActual(noActual, '0')).toEqual({ kind: 'send', value: '0' })
    expect(planPriceActual(withActual, 'Rp 0')).toEqual({ kind: 'send', value: '0' })
  })

  it('format Rupiah, pecahan, dan negatif', () => {
    expect(planPriceActual(noActual, 'Rp 12.500')).toEqual({ kind: 'send', value: '12500' })
    expect(planPriceActual(noActual, '12,5')).toMatchObject({ kind: 'invalid' })
    expect(planPriceActual(noActual, '-1')).toMatchObject({ kind: 'invalid' })
  })

  it('harga yang sama dengan harga aktual sekarang tidak dikirim; harga awal sesi bukan harga aktual', () => {
    expect(planPriceActual(withActual, '11.000')).toEqual({ kind: 'noop' })
    expect(planPriceActual(noActual, '10000')).toEqual({ kind: 'send', value: '10000' })
  })
})

describe('isi awal formulir', () => {
  it('jumlah aktual memakai koma; harga hanya bila harga aktual terisi', () => {
    expect(actualQuantityPrefill({ actual: '1.5' })).toBe('1,5')
    expect(actualQuantityPrefill({ actual: null })).toBe('')
    expect(priceActualPrefill({ price: '11000', priceIsActual: true })).toBe('11000')
    expect(priceActualPrefill({ price: '10000', priceIsActual: false })).toBe('')
    expect(priceActualPrefill({ price: null, priceIsActual: false })).toBe('')
  })
})

describe('teks setelah konfirmasi server', () => {
  it('menyebut dikonfirmasi server dan memakai format yang ada', () => {
    expect(statusOkText('Beras', 'in_cart')).toBe('Beras: status diubah menjadi Di keranjang (dikonfirmasi server).')
    expect(quantityOkText('Beras', '1.5', 'kg')).toBe('Jumlah aktual Beras menjadi 1,5 kg (dikonfirmasi server).')
    expect(quantityOkText('Beras', '2', '')).toBe('Jumlah aktual Beras menjadi 2 (dikonfirmasi server).')
    expect(priceOkText('Beras', '11000')).toBe('Harga aktual Beras menjadi Rp 11.000 (dikonfirmasi server).')
    expect(priceOkText('Beras', '0')).toBe('Harga aktual Beras menjadi Rp 0 (dikonfirmasi server).')
    expect(priceOkText('Beras', null)).toContain('dikosongkan')
  })
})
EOF

cat > "$B/sessionView3b.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { buildActiveView } from './sessionView'
import type { SessionItemRow, SessionRow } from './types'

const session = (): SessionRow => ({
  id: 's', workspace_id: 'w', status: 'active', started_by: null, started_at: '2026-11-20T07:00:00Z',
  ended_by: null, ended_at: null, total_estimate: '5000', unpriced_items_at_start: 0, total_actual: null,
  unpriced_items_purchased: null, created_at: '', updated_at: '',
})

const item = (id: string, extra: Partial<SessionItemRow> = {}): SessionItemRow => ({
  id, session_id: 's', workspace_id: 'w', source_item_id: 'src', product_id: null, product_name_snapshot: id,
  photo_path_snapshot: null, unit_snapshot: 'kg', unit_id_snapshot: null, allow_fraction_snapshot: true,
  note_snapshot: null, price_snapshot: '1000', price_actual: null, quantity_needed: '2', quantity_actual: null,
  status: 'to_buy', deleted_at: null, created_at: '', updated_at: '', ...extra,
})

describe('allowFraction dari snapshot', () => {
  it('mengikuti allow_fraction_snapshot per barang', () => {
    const v = buildActiveView(session(), [
      item('a', { allow_fraction_snapshot: true }),
      item('b', { allow_fraction_snapshot: false }),
    ])
    const by = Object.fromEntries(v.groups.flatMap((g) => g.items).map((i) => [i.id, i.allowFraction]))
    expect(by).toEqual({ a: true, b: false })
  })
})

describe('total berjalan mengikuti nilai server setelah penyegaran', () => {
  it('data baru dari server menghasilkan total berjalan baru; estimasi awal tetap nilai beku', () => {
    const before = buildActiveView(session(), [item('a', { status: 'to_buy' })])
    expect(before.running).toMatchObject({ total: '0', pricedCount: 0, unpricedCount: 0 })

    // Setelah server mengisi jumlah aktual awal = kebutuhan saat keluar dari to_buy (FR-032) dan layar disegarkan.
    const afterStatus = buildActiveView(session(), [item('a', { status: 'in_cart', quantity_actual: '2' })])
    expect(afterStatus.running).toMatchObject({ total: '2000', pricedCount: 1 })

    // Harga aktual dikonfirmasi server.
    const afterPrice = buildActiveView(session(), [
      item('a', { status: 'in_cart', quantity_actual: '2', price_actual: '1500' }),
    ])
    expect(afterPrice.running.total).toBe('3000')

    // Kembali ke to_buy: server mengosongkan jumlah aktual dan menyentuh price_actual tidak.
    const back = buildActiveView(session(), [item('a', { status: 'to_buy', quantity_actual: null, price_actual: '1500' })])
    expect(back.running).toMatchObject({ total: '0', pricedCount: 0 })
    expect(back.groups[0]?.items[0]).toMatchObject({ price: '1500', priceIsActual: true, subtotal: null })

    expect(before.frozen).toEqual(afterPrice.frozen)
    expect(before.frozen).toEqual({ total: '5000', unpricedCount: 0 })
  })

  it('barang tanpa harga tidak pernah menjadi Rp 0 dan menandai belum lengkap', () => {
    const v = buildActiveView(session(), [item('a', { status: 'in_cart', quantity_actual: '2', price_snapshot: null })])
    expect(v.running).toMatchObject({ total: '0', pricedCount: 0, unpricedCount: 1, incomplete: true })
    expect(v.groups[0]?.items[0]).toMatchObject({ price: null, subtotal: null })
  })

  it('total aktual berjalan tidak diekspos; hanya nilai beku saat selesai (FR-050)', () => {
    const v = buildActiveView(session(), [item('a', { status: 'purchased', quantity_actual: '2' })])
    expect(Object.keys(v).sort()).toEqual(['frozen', 'groups', 'itemCount', 'running', 'startedAt'])
  })
})
EOF

cat > "$B/useChecklist.ts" <<'EOF'
import { useMemo } from 'react'
import type { SubmitOptions } from '../daftar/submitCore'
import { isOnline } from '../katalog/catalogStore'
import { createBulkBatch } from './bulkBatch'
import { createItemOps } from './itemOps'
import type { SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

// Menghubungkan pengendali murni dengan titik tunggal penulisan sesi. Tidak ada pola kirim baru.
export function useChecklist(workspaceId: string) {
  return useMemo(() => {
    const common = {
      submit: (type: SessionOpType, payload: Record<string, unknown>, options: SubmitOptions) =>
        submitSessionOp(workspaceId, type, payload, options),
      newId: () => crypto.randomUUID(),
      isOnline,
      // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
      onDiscard: requestSessionRefresh,
    }
    return { items: createItemOps(common), bulk: createBulkBatch(common) }
  }, [workspaceId])
}

export type Checklist = ReturnType<typeof useChecklist>
EOF

cat > "$B/ChecklistStatus.tsx" <<'EOF'
import { useSyncExternalStore } from 'react'
import type { Checklist } from './useChecklist'

// Satu region status untuk seluruh daftar: hasil terakhir yang dikonfirmasi server dan alasan kontrol nonaktif.
export function ChecklistStatus({ checklist, online }: { checklist: Checklist; online: boolean }) {
  const { getLast, subscribe } = checklist.items
  const last = useSyncExternalStore(subscribe, getLast, getLast)
  if (online && last === null) return null
  return (
    <div className="space-y-1">
      {!online ? (
        <p role="status" className="text-sm">
          Anda sedang offline. Mengubah status, jumlah aktual, dan harga aktual memerlukan koneksi internet.
        </p>
      ) : null}
      {last ? (
        <p role="status" className="text-sm">
          {last.text}
        </p>
      ) : null}
    </div>
  )
}
EOF

cat > "$B/EditableSessionItemCard.tsx" <<'EOF'
import { useState, useSyncExternalStore } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { TextField } from '../daftar/TextField'
import {
  actualQuantityPrefill,
  planActualQuantity,
  planPriceActual,
  priceActualPrefill,
  priceOkText,
  quantityOkText,
  statusOkText,
} from './checklistForms'
import type { ItemOpState } from './itemOps'
import { SessionItemCard } from './SessionItemCard'
import { setPriceActualPayload, setQuantityActualPayload, setStatusPayload } from './sessionPayloads'
import { STATUS_LABEL, type SessionItemView } from './sessionView'
import { ITEM_STATUSES, type ItemStatus } from './types'
import type { Checklist } from './useChecklist'

type Editing = 'quantity' | 'price' | null

function ItemFailure({
  op,
  online,
  onRetry,
  onDismiss,
}: {
  op: ItemOpState
  online: boolean
  onRetry: () => void
  onDismiss: () => void
}) {
  const f = op.failure
  if (op.phase !== 'failed' || f === null) return null
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

export function EditableSessionItemCard({
  item,
  photoUrl,
  checklist,
  online,
}: {
  item: SessionItemView
  photoUrl: string | undefined
  checklist: Checklist
  online: boolean
}) {
  const { items: itemOps, bulk } = checklist
  const op = useSyncExternalStore(
    itemOps.subscribe,
    () => itemOps.getItem(item.id),
    () => itemOps.getItem(item.id),
  )
  const bulkState = useSyncExternalStore(bulk.subscribe, bulk.getState, bulk.getState)
  const [editing, setEditing] = useState<Editing>(null)
  const [text, setText] = useState('')
  const [error, setError] = useState<string | undefined>(undefined)

  const busy = op.phase === 'sending'
  const awaitingRetry = op.phase === 'failed' && op.failure !== null && op.failure.retryable
  const bulkHolds = bulkState.phase === 'confirm' || bulkState.phase === 'running' || bulkState.phase === 'halted'
  const blocked = busy || awaitingRetry || bulkHolds || !online
  const locked = busy || awaitingRetry

  function open(kind: 'quantity' | 'price') {
    setEditing(kind)
    setError(undefined)
    setText(kind === 'quantity' ? actualQuantityPrefill(item) : priceActualPrefill(item))
  }

  async function changeStatus(next: ItemStatus) {
    if (next === item.status || blocked) return
    await itemOps.run(item.id, 'session_set_status', setStatusPayload(item.id, next), statusOkText(item.name, next))
  }

  async function saveQuantity() {
    const plan = planActualQuantity(item, text)
    if (plan.kind === 'invalid') {
      setError(plan.message)
      return
    }
    setError(undefined)
    if (plan.kind === 'noop') {
      setEditing(null)
      return
    }
    const out = await itemOps.run(
      item.id,
      'session_set_quantity_actual',
      setQuantityActualPayload(item.id, plan.value),
      quantityOkText(item.name, plan.value, item.unitName),
    )
    if (out.status === 'ok') setEditing(null)
  }

  async function savePrice() {
    const plan = planPriceActual(item, text)
    if (plan.kind === 'invalid') {
      setError(plan.message)
      return
    }
    setError(undefined)
    if (plan.kind === 'noop') {
      setEditing(null)
      return
    }
    const out = await itemOps.run(
      item.id,
      'session_set_price_actual',
      setPriceActualPayload(item.id, plan.value),
      priceOkText(item.name, plan.value),
    )
    if (out.status === 'ok') setEditing(null)
  }

  async function retry() {
    const out = await itemOps.retry(item.id)
    if (out.status === 'ok') setEditing(null)
  }

  const saving = (
    <button type="submit" className={btnPrimary} disabled={locked || bulkHolds || !online}>
      {busy ? 'Menyimpan...' : 'Simpan'}
    </button>
  )

  return (
    <SessionItemCard item={item} photoUrl={photoUrl}>
      <fieldset disabled={blocked} className="min-w-0 space-y-1 pt-2">
        <legend className="text-sm font-semibold">Status {item.name}</legend>
        <div className="flex flex-wrap gap-2">
          {ITEM_STATUSES.map((s) => (
            <label
              key={s}
              className={`flex min-h-12 items-center gap-2 rounded-md bg-white px-3 text-base ring-1 ring-black/25 ${
                blocked ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'
              }`}
            >
              <input
                type="radio"
                name={`status-${item.id}`}
                value={s}
                checked={item.status === s}
                onChange={() => void changeStatus(s)}
                className="h-5 w-5"
              />
              {STATUS_LABEL[s]}
            </label>
          ))}
        </div>
      </fieldset>
      {busy ? (
        <p role="status" className="text-sm">
          Menyimpan...
        </p>
      ) : null}

      {editing === null ? (
        <div className="flex flex-wrap gap-2 pt-1">
          {item.status === 'to_buy' ? (
            <p className="w-full text-xs text-ink/75">Jumlah aktual diisi setelah barang masuk keranjang.</p>
          ) : (
            <button type="button" className={btnSecondary} onClick={() => open('quantity')} disabled={blocked}>
              Ubah jumlah aktual
            </button>
          )}
          <button type="button" className={btnSecondary} onClick={() => open('price')} disabled={blocked}>
            Ubah harga aktual
          </button>
        </div>
      ) : editing === 'quantity' ? (
        <form
          noValidate
          onSubmit={(e) => {
            e.preventDefault()
            void saveQuantity()
          }}
          className="space-y-2 pt-1"
        >
          <TextField
            id={`jumlah-aktual-${item.id}`}
            label="Jumlah aktual"
            value={text}
            onChange={setText}
            error={error}
            inputMode={item.allowFraction ? 'decimal' : 'numeric'}
            hint={
              item.allowFraction
                ? 'Boleh 0 dan berpecahan, maksimal 3 angka di belakang koma.'
                : 'Satuan ini hanya menerima bilangan bulat. Boleh 0.'
            }
            readOnly={locked}
          />
          <div className="flex flex-wrap gap-2">
            {saving}
            <button type="button" className={btnSecondary} onClick={() => setEditing(null)} disabled={locked}>
              Batal
            </button>
          </div>
        </form>
      ) : (
        <form
          noValidate
          onSubmit={(e) => {
            e.preventDefault()
            void savePrice()
          }}
          className="space-y-2 pt-1"
        >
          <TextField
            id={`harga-aktual-${item.id}`}
            label="Harga satuan aktual (Rp)"
            value={text}
            onChange={setText}
            error={error}
            inputMode="numeric"
            hint="Rupiah bulat. Kosongkan untuk memakai harga awal sesi. 0 diterima sebagai harga."
            readOnly={locked}
          />
          <div className="flex flex-wrap gap-2">
            {saving}
            <button type="button" className={btnSecondary} onClick={() => setEditing(null)} disabled={locked}>
              Batal
            </button>
          </div>
        </form>
      )}

      <ItemFailure op={op} online={online} onRetry={() => void retry()} onDismiss={() => itemOps.dismiss(item.id)} />
    </SessionItemCard>
  )
}
EOF

cat > "$B/BulkPurchase.tsx" <<'EOF'
import { useSyncExternalStore } from 'react'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { buildBulkReport, bulkConfirmMessage, bulkSummaryLine, type BulkItem } from './bulkBatch'
import type { Checklist } from './useChecklist'

// Dipasang di tingkat sesi, bukan di dalam kelompok "Di keranjang": kelompok itu hilang saat semua barang sudah dibeli,
// padahal laporan batch harus tetap terlihat.
export function BulkPurchase({
  checklist,
  items,
  online,
}: {
  checklist: Checklist
  items: BulkItem[]
  online: boolean
}) {
  const { bulk, items: itemOps } = checklist
  const state = useSyncExternalStore(bulk.subscribe, bulk.getState, bulk.getState)
  const itemBusy = useSyncExternalStore(itemOps.subscribe, itemOps.anyBusy, itemOps.anyBusy)
  const phase = state.phase
  if (phase === 'idle' && items.length === 0) return null

  const report = buildBulkReport(state)
  const processed = report.ok + report.rejected.length
  const current = state.entries[state.cursor]
  const showButton = (phase === 'idle' || phase === 'done') && items.length > 0
  const reason = !online
    ? 'Anda sedang offline. Aksi massal memerlukan koneksi internet.'
    : itemBusy
      ? 'Menunggu perubahan barang yang sedang disimpan.'
      : null

  return (
    <section aria-labelledby="aksi-massal" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="aksi-massal" className="font-semibold">
        Aksi massal
      </h2>

      {showButton ? (
        <>
          <button
            type="button"
            className={btnPrimary}
            onClick={() => bulk.open(items)}
            disabled={reason !== null}
          >
            Tandai semua isi keranjang sebagai dibeli
          </button>
          {reason ? <p className="text-sm">{reason}</p> : null}
        </>
      ) : null}

      {phase === 'running' ? (
        <p role="status" className="text-sm">
          Memproses {processed + 1} dari {report.total}
          {current ? `: ${current.name}` : ''}. Setiap barang dikonfirmasi server satu per satu.
        </p>
      ) : null}

      {phase === 'halted' && state.halt ? (
        <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
          <p className="break-words">{state.halt.message}</p>
          <p>{bulkSummaryLine(report)}</p>
          {report.rejected.length > 0 ? (
            <ul className="list-disc space-y-1 pl-5">
              {report.rejected.map((r) => (
                <li key={r.id} className="break-words">
                  <span className="font-semibold">{r.name}</span>: {r.message}
                </li>
              ))}
            </ul>
          ) : null}
          <p className="text-xs">
            Mengirim ulang aman dan tidak menggandakan hasil. Bila dihentikan, sisa barang tidak diproses dan layar
            disegarkan dari server.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={() => void bulk.retry()} disabled={!online}>
              Coba lagi
            </button>
            <button type="button" className={btnSecondary} onClick={() => bulk.discard()}>
              Hentikan
            </button>
          </div>
        </div>
      ) : null}

      {phase === 'done' ? (
        <div
          role={report.rejected.length > 0 || report.discarded ? 'alert' : 'status'}
          className="space-y-2 rounded-md bg-white p-3 text-sm ring-1 ring-black/25"
        >
          <p>{bulkSummaryLine(report)}</p>
          {report.discarded ? <p>Pemrosesan dihentikan. Layar disegarkan dari server.</p> : null}
          {report.rejected.length > 0 ? (
            <ul className="list-disc space-y-1 pl-5">
              {report.rejected.map((r) => (
                <li key={r.id} className="break-words">
                  <span className="font-semibold">{r.name}</span>: {r.message}
                </li>
              ))}
            </ul>
          ) : null}
          <button type="button" className={btnSecondary} onClick={() => bulk.close()}>
            Tutup laporan
          </button>
        </div>
      ) : null}

      <ConfirmDialog
        open={phase === 'confirm'}
        title="Tandai semua isi keranjang sebagai dibeli?"
        message={bulkConfirmMessage(state.entries.length)}
        confirmLabel={`Tandai ${state.entries.length} barang`}
        cancelLabel="Batal"
        onConfirm={() => void bulk.confirm()}
        onCancel={() => bulk.cancel()}
      />
    </section>
  )
}
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run && npm run build"
