#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
need() { grep -qF -- "$2" "$1" || fail "$1 tidak memuat: $2"; }

D=src/features/daftar

# --- Pemeriksaan awal (tidak mengubah apa pun) ---
for f in "$D/DaftarView.tsx" "$D/ListItemCard.tsx" "$D/useList.ts" "$D/listView.ts" "$D/listSync.ts" \
  "$D/submitListOp.ts" "$D/submitCore.ts" "$D/payloads.ts" "$D/validation.ts" "$D/format.ts" "$D/types.ts" \
  src/components/ConfirmDialog.tsx src/components/ui.ts src/lib/money.ts \
  src/features/katalog/photoCompress.ts src/features/katalog/photoUpload.ts \
  src/features/katalog/types.ts src/features/katalog/useCatalog.ts; do
  [ -f "$f" ] || fail "berkas tidak ada (Bagian 1 dan 2 sudah dijalankan?): $f"
done
for f in AddArea.tsx AddCatalogForm.tsx AddManualForm.tsx EditableItemCard.tsx OpNotice.tsx TextField.tsx \
  attemptRunner.ts attemptRunner.test.ts catalogSearch.ts catalogSearch.test.ts pendingPhotos.ts photoDeps.ts \
  photoFlow.ts photoFlow.test.ts useListOp.ts useOnline.ts; do
  [ ! -e "$D/$f" ] || fail "$D/$f sudah ada; tidak ditimpa"
done

need src/components/ConfirmDialog.tsx 'export default'
need src/components/ui.ts 'export const btnPrimary'
need src/components/ui.ts 'export const btnSecondary'
need src/components/ui.ts 'export const inputClass'
need src/features/katalog/photoCompress.ts 'export async function compressImage('
need src/features/katalog/photoCompress.ts 'export interface CompressedPhoto'
need src/features/katalog/photoUpload.ts 'export async function uploadProductPhoto('
need src/features/katalog/types.ts 'export type Result<T>'
need src/features/katalog/useCatalog.ts 'export function useCatalog('
need src/lib/money.ts 'export function formatRupiah('
need "$D/submitListOp.ts" 'export function submitListOp('
need "$D/submitCore.ts" 'export interface SubmitOptions'
need "$D/listSync.ts" 'export const requestListRefresh'
need "$D/payloads.ts" 'export function addCatalogPayload('
need "$D/payloads.ts" 'export function addManualPayload('
need "$D/payloads.ts" 'export const setQuantityPayload'
need "$D/payloads.ts" 'export const deletePayload'
need "$D/payloads.ts" 'export const setPhotoPayload'
need "$D/validation.ts" 'export function parseQuantityInput('
need "$D/validation.ts" 'export function validateManualItemForm('
need "$D/validation.ts" 'export function validateCatalogAddForm('
need "$D/format.ts" 'export function formatQuantity('
need "$D/listView.ts" 'export interface ListViewRow'
! grep -qF 'EditableItemCard' "$D/DaftarView.tsx" || fail "DaftarView.tsx sudah diubah oleh bagian ini"

# Patch dicek dulu (tanpa menulis), lalu diterapkan setelah semua berkas baru siap.
PATCHPY="$(mktemp)"
cat > "$PATCHPY" <<'PY'
import sys
check = len(sys.argv) > 1 and sys.argv[1] == "--check"
D = "src/features/daftar/"

EDITS = {
  D + "ListItemCard.tsx": [
    ("import { useState } from 'react'",
     "import { useState, type ReactNode } from 'react'"),
    ("  catalogStatus,",
     "  catalogStatus,\n  children,"),
    ("  catalogStatus: SyncStatus",
     "  catalogStatus: SyncStatus\n  children?: ReactNode"),
    ('''          <p className="text-sm">Harga belum tersedia</p>
        )}
      </div>
    </li>''',
     '''          <p className="text-sm">Harga belum tersedia</p>
        )}
        {children}
      </div>
    </li>'''),
  ],
  D + "DaftarView.tsx": [
    ("import { useMemo, type ReactNode } from 'react'",
     "import { useMemo, useState, type ReactNode } from 'react'"),
    ("import { ListItemCard } from './ListItemCard'",
     "import { AddArea } from './AddArea'\nimport { EditableItemCard } from './EditableItemCard'"),
    ("import { useDaftar } from './useList'",
     "import { useDaftar } from './useList'\nimport { useOnline } from './useOnline'"),
    ("  const busy = sync.status === 'syncing'",
     "  const busy = sync.status === 'syncing'\n  const online = useOnline()\n  const [feedback, setFeedback] = useState<string | null>(null)"),
    ("{readError !== null ? (",
     '''{feedback ? (
        <div
          role="status"
          className="flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ring-black/25"
        >
          <p className="min-w-0 break-words">{feedback}</p>
          <button
            type="button"
            className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
            onClick={() => setFeedback(null)}
          >
            Tutup
          </button>
        </div>
      ) : null}
      {view ? (
        <AddArea workspaceId={workspaceId} rows={view.rows} online={online} onFeedback={setFeedback} />
      ) : null}
      {readError !== null ? ('''),
    ("<ListItemCard", "<EditableItemCard"),
    ("catalogStatus={catalogSync.status}",
     "catalogStatus={catalogSync.status}\n                    workspaceId={workspaceId}\n                    online={online}\n                    onFeedback={setFeedback}"),
    ("Menambah barang belum tersedia dan\n          menyusul di bagian berikutnya.",
     "Gunakan tombol tambah di atas."),
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
python3 "$PATCHPY" --check

# --- Penulisan berkas baru ---
cat > "$D/useOnline.ts" <<'EOF'
import { useSyncExternalStore } from 'react'

function subscribe(listener: () => void): () => void {
  window.addEventListener('online', listener)
  window.addEventListener('offline', listener)
  return () => {
    window.removeEventListener('online', listener)
    window.removeEventListener('offline', listener)
  }
}

export function useOnline(): boolean {
  return useSyncExternalStore(subscribe, () => navigator.onLine, () => true)
}
EOF

cat > "$D/attemptRunner.ts" <<'EOF'
import type { SubmitOptions } from './submitCore'
import type { ListOpResult, ListOpType } from './types'

type Payload = Record<string, unknown>
type Submit = (type: ListOpType, payload: Payload, options: SubmitOptions) => Promise<ListOpResult>
interface Attempt {
  opId: string
  type: ListOpType
  payload: Payload
}

// Satu percobaan yang gagal dengan retryable disimpan, lalu dikirim ulang dengan opId dan payload yang sama.
export function createAttemptRunner(submit: Submit, newId: () => string) {
  let attempt: Attempt | null = null

  async function send(a: Attempt): Promise<ListOpResult> {
    const r = await submit(a.type, a.payload, { opId: a.opId })
    attempt = !r.ok && r.retryable ? a : null
    return r
  }

  return {
    run: (type: ListOpType, payload: Payload): Promise<ListOpResult> => send({ opId: newId(), type, payload }),
    retry: async (): Promise<ListOpResult | null> => (attempt ? send(attempt) : null),
    discard: (): void => {
      attempt = null
    },
    hasPending: (): boolean => attempt !== null,
  }
}
EOF

cat > "$D/attemptRunner.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import { createAttemptRunner } from './attemptRunner'
import type { ListOpResult } from './types'

const ok = (opId: string): ListOpResult => ({ ok: true, opId, data: {}, replayed: false })
const bad = (opId: string, retryable: boolean): ListOpResult => ({
  ok: false,
  opId,
  code: 'X',
  message: 'pesan',
  retryable,
})

function setup(results: ListOpResult[]) {
  const calls: Array<{ type: string; payload: Record<string, unknown>; opId: string | undefined }> = []
  let n = 0
  const runner = createAttemptRunner(
    async (type, payload, options) => {
      calls.push({ type, payload, opId: options.opId })
      const r = results.shift()
      if (!r) throw new Error('tidak ada hasil terjadwal')
      return r
    },
    () => `op-${++n}`,
  )
  return { runner, calls }
}

describe('createAttemptRunner', () => {
  it('sukses tidak menyisakan percobaan', async () => {
    const { runner, calls } = setup([ok('op-1')])
    await runner.run('list_delete', { item_id: 'i1' })
    expect(runner.hasPending()).toBe(false)
    expect(calls[0]).toEqual({ type: 'list_delete', payload: { item_id: 'i1' }, opId: 'op-1' })
  })

  it('gagal retryable dikirim ulang dengan opId dan payload yang sama', async () => {
    const { runner, calls } = setup([bad('op-1', true), ok('op-1')])
    await runner.run('list_set_quantity', { item_id: 'i1', quantity: 2 })
    expect(runner.hasPending()).toBe(true)
    const r = await runner.retry()
    expect(r?.ok).toBe(true)
    expect(runner.hasPending()).toBe(false)
    expect(calls).toHaveLength(2)
    expect(calls[1]).toEqual(calls[0])
  })

  it('retry yang gagal lagi tetap memakai opId yang sama', async () => {
    const { runner, calls } = setup([bad('op-1', true), bad('op-1', true)])
    await runner.run('list_delete', { item_id: 'i1' })
    await runner.retry()
    expect(runner.hasPending()).toBe(true)
    expect(calls[1]?.opId).toBe('op-1')
  })

  it('gagal tidak retryable membersihkan percobaan dan retry tidak mengirim apa pun', async () => {
    const { runner, calls } = setup([bad('op-1', false)])
    await runner.run('list_delete', { item_id: 'i1' })
    expect(runner.hasPending()).toBe(false)
    expect(await runner.retry()).toBeNull()
    expect(calls).toHaveLength(1)
  })

  it('discard membuang percobaan dan operasi berikutnya memakai opId baru', async () => {
    const { runner, calls } = setup([bad('op-1', true), ok('op-2')])
    await runner.run('list_delete', { item_id: 'i1' })
    runner.discard()
    expect(runner.hasPending()).toBe(false)
    await runner.run('list_delete', { item_id: 'i2' })
    expect(calls[1]?.opId).toBe('op-2')
  })
})
EOF

cat > "$D/photoFlow.ts" <<'EOF'
import type { CompressedPhoto } from '../katalog/photoCompress'
import type { Result } from '../katalog/types'

export interface PhotoFlowDeps {
  compress: (file: File) => Promise<Result<CompressedPhoto>>
  upload: (workspaceId: string, blob: Blob, mime: string) => Promise<Result<string>>
}

export type PhotoPrep =
  | { kind: 'none' }
  | { kind: 'ready'; path: string; blob: Blob; mime: string }
  | { kind: 'upload_failed'; blob: Blob; mime: string; message: string }
  | { kind: 'invalid'; message: string }

// Unggah ke path baru lebih dulu; kegagalan unggah tidak membatalkan barangnya (FR-013, SYNC-019).
export async function uploadPrepared(
  deps: PhotoFlowDeps,
  workspaceId: string,
  blob: Blob,
  mime: string,
): Promise<PhotoPrep> {
  const up = await deps.upload(workspaceId, blob, mime)
  if (!up.ok) return { kind: 'upload_failed', blob, mime, message: up.error.message }
  return { kind: 'ready', path: up.data, blob, mime }
}

export async function preparePhoto(deps: PhotoFlowDeps, workspaceId: string, file: File | null): Promise<PhotoPrep> {
  if (!file) return { kind: 'none' }
  const c = await deps.compress(file)
  if (!c.ok) return { kind: 'invalid', message: c.error.message }
  return uploadPrepared(deps, workspaceId, c.data.blob, c.data.mime)
}
EOF

cat > "$D/photoFlow.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { CompressedPhoto } from '../katalog/photoCompress'
import type { Result } from '../katalog/types'
import { preparePhoto, uploadPrepared, type PhotoFlowDeps } from './photoFlow'

const blob = new Blob(['x'])
const file = blob as unknown as File

function makeDeps(compress: Result<CompressedPhoto>, upload: Result<string>) {
  const counts = { compress: 0, upload: 0 }
  const deps: PhotoFlowDeps = {
    compress: async () => {
      counts.compress += 1
      return compress
    },
    upload: async () => {
      counts.upload += 1
      return upload
    },
  }
  return { deps, counts }
}

const compressed: Result<CompressedPhoto> = { ok: true, data: { blob, mime: 'image/webp' } }
const uploaded: Result<string> = { ok: true, data: 'w/abc.webp' }
const err = (message: string) => ({ ok: false as const, error: { code: 'E', message } })

describe('preparePhoto', () => {
  it('tanpa berkas tidak memanggil apa pun', async () => {
    const { deps, counts } = makeDeps(compressed, uploaded)
    expect(await preparePhoto(deps, 'w', null)).toEqual({ kind: 'none' })
    expect(counts).toEqual({ compress: 0, upload: 0 })
  })

  it('gagal kompres berarti tidak valid dan tidak mengunggah', async () => {
    const { deps, counts } = makeDeps(err('terlalu besar'), uploaded)
    expect(await preparePhoto(deps, 'w', file)).toEqual({ kind: 'invalid', message: 'terlalu besar' })
    expect(counts.upload).toBe(0)
  })

  it('gagal unggah mempertahankan hasil kompres untuk dicoba lagi', async () => {
    const { deps } = makeDeps(compressed, err('Tidak ada koneksi internet.'))
    expect(await preparePhoto(deps, 'w', file)).toEqual({
      kind: 'upload_failed',
      blob,
      mime: 'image/webp',
      message: 'Tidak ada koneksi internet.',
    })
  })

  it('sukses mengembalikan path baru', async () => {
    const { deps } = makeDeps(compressed, uploaded)
    expect(await preparePhoto(deps, 'w', file)).toEqual({ kind: 'ready', path: 'w/abc.webp', blob, mime: 'image/webp' })
  })
})

describe('uploadPrepared', () => {
  it('mengunggah ulang blob tersimpan tanpa kompres lagi', async () => {
    const { deps, counts } = makeDeps(compressed, uploaded)
    const r = await uploadPrepared(deps, 'w', blob, 'image/webp')
    expect(r.kind).toBe('ready')
    expect(counts).toEqual({ compress: 0, upload: 1 })
  })
})
EOF

cat > "$D/photoDeps.ts" <<'EOF'
import { compressImage } from '../katalog/photoCompress'
import { uploadProductPhoto } from '../katalog/photoUpload'
import type { PhotoFlowDeps } from './photoFlow'

export const photoDeps: PhotoFlowDeps = { compress: compressImage, upload: uploadProductPhoto }
EOF

cat > "$D/pendingPhotos.ts" <<'EOF'
import { useSyncExternalStore } from 'react'

export interface PendingPhoto {
  blob: Blob
  mime: string
}

// Hanya di memori: hilang bila halaman dimuat ulang. Tahap 6 memindahkannya ke antrean offline.
const store = new Map<string, PendingPhoto>()
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export function setPendingPhoto(itemId: string, photo: PendingPhoto): void {
  store.set(itemId, photo)
  emit()
}

export function clearPendingPhoto(itemId: string): void {
  if (store.delete(itemId)) emit()
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function usePendingPhoto(itemId: string): PendingPhoto | undefined {
  return useSyncExternalStore(subscribe, () => store.get(itemId), () => undefined)
}
EOF

cat > "$D/catalogSearch.ts" <<'EOF'
import type { CatalogData } from '../katalog/types'

export interface CatalogHit {
  id: string
  name: string
  unitName: string
  allowFraction: boolean
  price: string | null
}

export interface SearchResult {
  hits: CatalogHit[]
  total: number
  activeCount: number
}

function toHit(data: CatalogData, p: CatalogData['products'][number]): CatalogHit {
  const unit = data.units.find((u) => u.id === p.unit_id)
  return { id: p.id, name: p.name, unitName: unit?.name ?? '', allowFraction: unit?.allow_fraction ?? false, price: p.price }
}

// Hanya barang aktif yang dapat ditambahkan (FR-008). Pencarian dari data lokal (FR-007).
export function searchProducts(data: CatalogData, query: string, limit: number): SearchResult {
  const q = query.trim().toLowerCase()
  const active = data.products.filter((p) => !p.is_archived)
  const matched = (q === '' ? active : active.filter((p) => p.name.toLowerCase().includes(q))).sort(
    (a, b) => a.name.localeCompare(b.name, 'id') || a.id.localeCompare(b.id),
  )
  return { hits: matched.slice(0, limit).map((p) => toHit(data, p)), total: matched.length, activeCount: active.length }
}

export function findHit(data: CatalogData, id: string): CatalogHit | null {
  const p = data.products.find((x) => x.id === id && !x.is_archived)
  return p ? toHit(data, p) : null
}
EOF

cat > "$D/catalogSearch.test.ts" <<'EOF'
import { describe, expect, it } from 'vitest'
import type { CatalogData, ProductRow } from '../katalog/types'
import { findHit, searchProducts } from './catalogSearch'

const p = (id: string, name: string, extra: Partial<ProductRow> = {}): ProductRow => ({
  id,
  workspace_id: 'w',
  category_id: 'c',
  unit_id: 'u-kg',
  name,
  photo_path: null,
  price: null,
  is_archived: false,
  updated_at: '',
  ...extra,
})

const data: CatalogData = {
  categories: [],
  units: [{ id: 'u-kg', workspace_id: 'w', name: 'kg', is_archived: false, updated_at: '', allow_fraction: true }],
  products: [p('1', 'Gula pasir', { price: '15000' }), p('2', 'Beras'), p('3', 'Gula merah', { is_archived: true }), p('4', 'gula aren')],
}

describe('searchProducts', () => {
  it('mengabaikan huruf besar kecil, membuang barang arsip, dan mengurutkan nama', () => {
    const r = searchProducts(data, ' GULA ', 10)
    expect(r.hits.map((h) => h.name)).toEqual(['gula aren', 'Gula pasir'])
    expect(r.total).toBe(2)
  })

  it('kueri kosong menampilkan semua barang aktif dan membatasi jumlah tampil', () => {
    const r = searchProducts(data, '', 2)
    expect(r.hits).toHaveLength(2)
    expect(r.total).toBe(3)
    expect(r.activeCount).toBe(3)
  })

  it('membawa satuan, aturan pecahan, dan harga', () => {
    const hit = searchProducts(data, 'pasir', 5).hits[0]
    expect(hit).toEqual({ id: '1', name: 'Gula pasir', unitName: 'kg', allowFraction: true, price: '15000' })
  })
})

describe('findHit', () => {
  it('tidak menemukan barang arsip atau yang tidak ada', () => {
    expect(findHit(data, '3')).toBeNull()
    expect(findHit(data, 'x')).toBeNull()
    expect(findHit(data, '2')?.name).toBe('Beras')
  })
})
EOF

cat > "$D/useListOp.ts" <<'EOF'
import { useCallback, useMemo, useRef, useState } from 'react'
import { createAttemptRunner } from './attemptRunner'
import { requestListRefresh } from './listSync'
import { submitListOp } from './submitListOp'
import type { ListOpResult, ListOpType } from './types'

export type OpOk = Extract<ListOpResult, { ok: true }>

// Satu operasi pada satu waktu per pemakai hook. Gagal retryable disimpan untuk dikirim ulang dengan op_id yang sama.
export function useListOp(workspaceId: string) {
  const runner = useMemo(
    () =>
      createAttemptRunner(
        (type, payload, options) => submitListOp(workspaceId, type, payload, options),
        () => crypto.randomUUID(),
      ),
    [workspaceId],
  )
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)
  const after = useRef<((r: OpOk) => void) | null>(null)

  const finish = useCallback(
    (r: ListOpResult | null): ListOpResult | null => {
      setBusy(false)
      setPending(runner.hasPending())
      if (r === null) return r
      setError(r.ok ? null : r.message)
      // Ditolak server: ambil data terbaru supaya layar sama dengan server.
      if (!r.ok && !r.retryable && r.code !== 'OFFLINE' && r.code !== 'NO_CLIENT') requestListRefresh()
      return r
    },
    [runner],
  )

  const run = useCallback(
    async (type: ListOpType, payload: Record<string, unknown>, onOk: (r: OpOk) => void) => {
      after.current = onOk
      setBusy(true)
      setError(null)
      const r = finish(await runner.run(type, payload))
      if (r && r.ok) onOk(r)
      return r
    },
    [runner, finish],
  )

  const retry = useCallback(async () => {
    setBusy(true)
    setError(null)
    const r = finish(await runner.retry())
    if (r && r.ok) after.current?.(r)
    return r
  }, [runner, finish])

  const discard = useCallback(() => {
    runner.discard()
    setPending(false)
    setError(null)
    requestListRefresh()
  }, [runner])

  return { busy, error, pending, run, retry, discard }
}
EOF

cat > "$D/OpNotice.tsx" <<'EOF'
import { btnSecondary } from '../../components/ui'

export function OpNotice({
  error,
  pending,
  busy,
  onRetry,
  onDiscard,
}: {
  error: string | null
  pending: boolean
  busy: boolean
  onRetry: () => void
  onDiscard: () => void
}) {
  if (!error && !pending) return null
  return (
    <div role="alert" className="space-y-2 rounded-md bg-white p-3 text-sm text-red-900 ring-1 ring-red-800/60">
      {error ? <p className="break-words">{error}</p> : null}
      {pending ? (
        <>
          <p>Perubahan ini mungkin sudah tersimpan di server. Mengirim ulang aman dan tidak menggandakan barang.</p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnSecondary} onClick={onRetry} disabled={busy}>
              {busy ? 'Mengirim...' : 'Coba lagi'}
            </button>
            <button type="button" className={btnSecondary} onClick={onDiscard} disabled={busy}>
              Batalkan
            </button>
          </div>
        </>
      ) : null}
    </div>
  )
}
EOF

cat > "$D/TextField.tsx" <<'EOF'
import { inputClass } from '../../components/ui'

export function TextField({
  id,
  label,
  value,
  onChange,
  error,
  hint,
  inputMode,
  multiline,
  readOnly,
}: {
  id: string
  label: string
  value: string
  onChange: (v: string) => void
  error?: string | undefined
  hint?: string | undefined
  inputMode?: 'text' | 'decimal' | 'numeric' | undefined
  multiline?: boolean | undefined
  readOnly?: boolean | undefined
}) {
  const describedBy = [hint ? `${id}-hint` : '', error ? `${id}-err` : ''].filter(Boolean).join(' ') || undefined
  return (
    <div className="space-y-1">
      <label htmlFor={id} className="block text-sm font-semibold">
        {label}
      </label>
      {multiline ? (
        <textarea
          id={id}
          rows={3}
          value={value}
          readOnly={readOnly}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          onChange={(e) => onChange(e.target.value)}
          className={`${inputClass} py-2`}
        />
      ) : (
        <input
          id={id}
          type="text"
          inputMode={inputMode}
          autoComplete="off"
          value={value}
          readOnly={readOnly}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        />
      )}
      {hint ? (
        <p id={`${id}-hint`} className="text-xs text-ink/75">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={`${id}-err`} className="text-sm text-red-900">
          {error}
        </p>
      ) : null}
    </div>
  )
}
EOF

cat > "$D/AddCatalogForm.tsx" <<'EOF'
import { useMemo, useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { formatRupiah } from '../../lib/money'
import { useCatalog } from '../katalog/useCatalog'
import { findHit, searchProducts } from './catalogSearch'
import { formatQuantity } from './format'
import type { ListViewRow } from './listView'
import { OpNotice } from './OpNotice'
import { addCatalogPayload } from './payloads'
import { TextField } from './TextField'
import { useListOp } from './useListOp'
import { validateCatalogAddForm } from './validation'

const RESULT_LIMIT = 8

export function AddCatalogForm({
  workspaceId,
  rows,
  online,
  onDone,
  onCancel,
}: {
  workspaceId: string
  rows: ListViewRow[]
  online: boolean
  onDone: (message: string) => void
  onCancel: () => void
}) {
  const { data } = useCatalog(workspaceId)
  const op = useListOp(workspaceId)
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [qtyText, setQtyText] = useState('1')
  const [errors, setErrors] = useState<Partial<Record<'productId' | 'quantity', string>>>({})

  const search = useMemo(() => (data ? searchProducts(data, query, RESULT_LIMIT) : null), [data, query])
  const selected = data && selectedId ? findHit(data, selectedId) : null
  const existing = selected ? rows.find((r) => r.productId === selected.id) : undefined

  async function submit() {
    if (!selected) return
    const v = validateCatalogAddForm({
      productId: selected.id,
      quantityText: qtyText,
      allowFraction: selected.allowFraction,
    })
    if (!v.ok) {
      setErrors(v.errors)
      return
    }
    setErrors({})
    await op.run('add_catalog_to_list', addCatalogPayload(v.value.productId, v.value.quantity), (r) =>
      onDone(
        r.data.merged === true
          ? `${selected.name}: jumlah digabung dengan barang yang sudah ada di daftar.`
          : `${selected.name} ditambahkan ke daftar.`,
      ),
    )
  }

  if (!data || !search) return <p role="status">Memuat katalog dari perangkat...</p>

  if (search.activeCount === 0) {
    return (
      <div className="space-y-3">
        <p className="text-sm">
          Katalog belum memiliki barang aktif. Admin perlu menambahkan barang di menu Katalog lebih dulu, atau
          gunakan barang manual.
        </p>
        <button type="button" className={btnSecondary} onClick={onCancel}>
          Tutup
        </button>
      </div>
    )
  }

  if (!selected) {
    return (
      <div className="space-y-3">
        <TextField id="cari-katalog" label="Cari barang di katalog" value={query} onChange={setQuery} />
        {errors.productId ? <p className="text-sm text-red-900">{errors.productId}</p> : null}
        {search.hits.length === 0 ? (
          <p className="text-sm">Tidak ada barang aktif yang cocok dengan pencarian.</p>
        ) : (
          <ul className="space-y-2">
            {search.hits.map((h) => (
              <li key={h.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(h.id)}
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

  const locked = op.busy || op.pending
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
        <p className="break-words font-semibold">{selected.name}</p>
        <p className="text-sm">
          {selected.unitName}
          {selected.price !== null ? ` · ${formatRupiah(selected.price)}` : ' · Harga belum tersedia'}
        </p>
        <button type="button" className={btnSecondary} onClick={() => setSelectedId(null)} disabled={locked}>
          Ganti barang
        </button>
      </div>
      <TextField
        id="tambah-katalog-jumlah"
        label="Jumlah"
        value={qtyText}
        onChange={setQtyText}
        error={errors.quantity}
        inputMode={selected.allowFraction ? 'decimal' : 'numeric'}
        hint={
          selected.allowFraction
            ? 'Boleh berpecahan, maksimal 3 angka di belakang koma.'
            : 'Satuan ini hanya menerima bilangan bulat.'
        }
        readOnly={locked}
      />
      {existing ? (
        <p className="text-sm">
          Barang ini sudah ada di daftar ({formatQuantity(existing.quantity)} {existing.unitName}). Jumlah yang Anda
          masukkan akan digabung dengan jumlah tersebut.
        </p>
      ) : null}
      <OpNotice error={op.error} pending={op.pending} busy={op.busy} onRetry={() => void op.retry()} onDiscard={op.discard} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={btnPrimary} disabled={locked || !online}>
          {op.busy ? 'Menyimpan...' : 'Tambahkan ke daftar'}
        </button>
        <button type="button" className={btnSecondary} onClick={onCancel} disabled={locked}>
          Batal
        </button>
      </div>
      {!online ? <p className="text-sm">Anda sedang offline. Menambah barang memerlukan koneksi internet.</p> : null}
    </form>
  )
}
EOF

cat > "$D/AddManualForm.tsx" <<'EOF'
import { useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { OpNotice } from './OpNotice'
import { setPendingPhoto } from './pendingPhotos'
import { photoDeps } from './photoDeps'
import { preparePhoto } from './photoFlow'
import { addManualPayload } from './payloads'
import { TextField } from './TextField'
import { useListOp } from './useListOp'
import { validateManualItemForm } from './validation'

type FieldKey = 'name' | 'unit' | 'quantity' | 'note'

export function AddManualForm({
  workspaceId,
  online,
  onDone,
  onCancel,
}: {
  workspaceId: string
  online: boolean
  onDone: (message: string) => void
  onCancel: () => void
}) {
  const op = useListOp(workspaceId)
  const [name, setName] = useState('')
  const [qty, setQty] = useState('1')
  const [unit, setUnit] = useState('')
  const [note, setNote] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [errors, setErrors] = useState<Partial<Record<FieldKey, string>>>({})
  const [photoError, setPhotoError] = useState<string | null>(null)
  const [preparing, setPreparing] = useState(false)
  const locked = op.busy || preparing || op.pending

  async function submit() {
    const v = validateManualItemForm({ name, unit, quantityText: qty, note })
    if (!v.ok) {
      setErrors(v.errors)
      return
    }
    setErrors({})
    setPhotoError(null)

    setPreparing(true)
    const prep = await preparePhoto(photoDeps, workspaceId, file)
    setPreparing(false)
    if (prep.kind === 'invalid') {
      setPhotoError(prep.message)
      return
    }

    const id = crypto.randomUUID()
    const photoPath = prep.kind === 'ready' ? prep.path : null
    const later = prep.kind === 'upload_failed' ? prep : null
    await op.run('list_add_manual', addManualPayload({ id, ...v.value, photoPath }), () => {
      if (later) setPendingPhoto(id, { blob: later.blob, mime: later.mime })
      onDone(
        later
          ? `${v.value.name} ditambahkan, tetapi fotonya belum terunggah. Gunakan tombol foto pada barang itu untuk mencoba lagi.`
          : `${v.value.name} ditambahkan ke daftar.`,
      )
    })
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
      <TextField id="manual-nama" label="Nama barang" value={name} onChange={setName} error={errors.name} readOnly={locked} />
      <TextField
        id="manual-jumlah"
        label="Jumlah"
        value={qty}
        onChange={setQty}
        error={errors.quantity}
        inputMode="decimal"
        hint="Boleh berpecahan, maksimal 3 angka di belakang koma."
        readOnly={locked}
      />
      <TextField
        id="manual-satuan"
        label="Satuan"
        value={unit}
        onChange={setUnit}
        error={errors.unit}
        hint="Contoh: kg, pak, pcs."
        readOnly={locked}
      />
      <TextField
        id="manual-catatan"
        label="Catatan (opsional)"
        value={note}
        onChange={setNote}
        error={errors.note}
        multiline
        readOnly={locked}
      />
      <div className="space-y-1">
        <label htmlFor="manual-foto" className="block text-sm font-semibold">
          Foto (opsional)
        </label>
        <input
          id="manual-foto"
          type="file"
          accept="image/*"
          disabled={locked}
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          className="block w-full text-base file:mr-3 file:min-h-12 file:cursor-pointer file:rounded-md file:border-0 file:bg-white file:px-4 file:ring-1 file:ring-black/25"
        />
        <p className="text-xs text-ink/75">Barang manual tidak memiliki harga di daftar. Harga diisi saat belanja.</p>
        {photoError ? <p className="text-sm text-red-900">{photoError}</p> : null}
      </div>
      <OpNotice error={op.error} pending={op.pending} busy={op.busy} onRetry={() => void op.retry()} onDiscard={op.discard} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={btnPrimary} disabled={locked || !online}>
          {preparing ? 'Memproses foto...' : op.busy ? 'Menyimpan...' : 'Tambahkan ke daftar'}
        </button>
        <button type="button" className={btnSecondary} onClick={onCancel} disabled={locked}>
          Batal
        </button>
      </div>
      {!online ? <p className="text-sm">Anda sedang offline. Menambah barang memerlukan koneksi internet.</p> : null}
    </form>
  )
}
EOF

cat > "$D/AddArea.tsx" <<'EOF'
import { useState, type ReactNode } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { AddCatalogForm } from './AddCatalogForm'
import { AddManualForm } from './AddManualForm'
import type { ListViewRow } from './listView'

type Mode = 'closed' | 'catalog' | 'manual'

function Panel({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id={id} className="font-semibold">
        {title}
      </h2>
      {children}
    </section>
  )
}

export function AddArea({
  workspaceId,
  rows,
  online,
  onFeedback,
}: {
  workspaceId: string
  rows: ListViewRow[]
  online: boolean
  onFeedback: (message: string) => void
}) {
  const [mode, setMode] = useState<Mode>('closed')
  const done = (message: string) => {
    setMode('closed')
    onFeedback(message)
  }

  if (mode === 'catalog') {
    return (
      <Panel id="panel-katalog" title="Tambah dari katalog">
        <AddCatalogForm
          workspaceId={workspaceId}
          rows={rows}
          online={online}
          onDone={done}
          onCancel={() => setMode('closed')}
        />
      </Panel>
    )
  }
  if (mode === 'manual') {
    return (
      <Panel id="panel-manual" title="Tambah barang manual">
        <AddManualForm workspaceId={workspaceId} online={online} onDone={done} onCancel={() => setMode('closed')} />
      </Panel>
    )
  }
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <button type="button" className={btnPrimary} onClick={() => setMode('catalog')} disabled={!online}>
          Tambah dari katalog
        </button>
        <button type="button" className={btnSecondary} onClick={() => setMode('manual')} disabled={!online}>
          Tambah barang manual
        </button>
      </div>
      {!online ? (
        <p className="text-sm">Anda sedang offline. Menambah, mengubah, dan menghapus barang memerlukan koneksi internet.</p>
      ) : null}
    </div>
  )
}
EOF

cat > "$D/EditableItemCard.tsx" <<'EOF'
import { useRef, useState, type ChangeEvent } from 'react'
import ConfirmDialog from '../../components/ConfirmDialog'
import { btnPrimary, btnSecondary } from '../../components/ui'
import type { SyncStatus } from '../katalog/catalogSync'
import { formatQuantity } from './format'
import { ListItemCard } from './ListItemCard'
import type { ListViewRow } from './listView'
import { OpNotice } from './OpNotice'
import { clearPendingPhoto, setPendingPhoto, usePendingPhoto } from './pendingPhotos'
import { deletePayload, setPhotoPayload, setQuantityPayload } from './payloads'
import { photoDeps } from './photoDeps'
import { preparePhoto, uploadPrepared, type PhotoPrep } from './photoFlow'
import { TextField } from './TextField'
import { useListOp } from './useListOp'
import { parseQuantityInput } from './validation'

export function EditableItemCard({
  row,
  photoUrl,
  catalogStatus,
  workspaceId,
  online,
  onFeedback,
}: {
  row: ListViewRow
  photoUrl: string | undefined
  catalogStatus: SyncStatus
  workspaceId: string
  online: boolean
  onFeedback: (message: string) => void
}) {
  const op = useListOp(workspaceId)
  const pendingPhoto = usePendingPhoto(row.id)
  const fileRef = useRef<HTMLInputElement>(null)
  const [editing, setEditing] = useState(false)
  const [qtyText, setQtyText] = useState('')
  const [qtyError, setQtyError] = useState<string | undefined>(undefined)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [photoBusy, setPhotoBusy] = useState(false)
  const [photoMsg, setPhotoMsg] = useState<string | null>(null)

  const blocked = op.busy || photoBusy || op.pending || !online
  const unit = row.unitName ? ` ${row.unitName}` : ''
  const canAttachPhoto = row.kind === 'manual' && !row.photoPath

  function startEdit() {
    setQtyText(row.quantity.replace('.', ','))
    setQtyError(undefined)
    setEditing(true)
  }

  function saveQuantity() {
    const q = parseQuantityInput(qtyText, { allowFraction: row.allowFraction })
    if (!q.ok) {
      setQtyError(q.message)
      return
    }
    setQtyError(undefined)
    if (q.value === row.quantity) {
      setEditing(false)
      return
    }
    void op.run('list_set_quantity', setQuantityPayload(row.id, q.value), () => {
      setEditing(false)
      onFeedback(`Jumlah ${row.name} diubah menjadi ${formatQuantity(q.value)}${unit}.`)
    })
  }

  function remove() {
    setConfirmDelete(false)
    void op.run('list_delete', deletePayload(row.id), () => onFeedback(`${row.name} dihapus dari daftar.`))
  }

  async function attach(prep: PhotoPrep) {
    if (prep.kind === 'invalid') {
      setPhotoMsg(prep.message)
      return
    }
    if (prep.kind === 'upload_failed') {
      setPendingPhoto(row.id, { blob: prep.blob, mime: prep.mime })
      setPhotoMsg(`${prep.message} Foto disimpan sementara di perangkat ini sampai halaman dimuat ulang.`)
      return
    }
    if (prep.kind !== 'ready') return
    await op.run('list_set_photo', setPhotoPayload(row.id, prep.path), () => {
      clearPendingPhoto(row.id)
      onFeedback(`Foto ${row.name} dipasang.`)
    })
  }

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null
    e.target.value = ''
    if (!file) return
    setPhotoBusy(true)
    setPhotoMsg(null)
    const prep = await preparePhoto(photoDeps, workspaceId, file)
    setPhotoBusy(false)
    await attach(prep)
  }

  async function retryStoredPhoto() {
    if (!pendingPhoto) return
    setPhotoBusy(true)
    setPhotoMsg(null)
    const prep = await uploadPrepared(photoDeps, workspaceId, pendingPhoto.blob, pendingPhoto.mime)
    setPhotoBusy(false)
    await attach(prep)
  }

  return (
    <ListItemCard row={row} photoUrl={photoUrl} catalogStatus={catalogStatus}>
      {editing ? (
        <form
          noValidate
          onSubmit={(e) => {
            e.preventDefault()
            saveQuantity()
          }}
          className="space-y-2 pt-1"
        >
          <TextField
            id={`jumlah-${row.id}`}
            label="Jumlah baru"
            value={qtyText}
            onChange={setQtyText}
            error={qtyError}
            inputMode={row.allowFraction ? 'decimal' : 'numeric'}
            hint={row.allowFraction ? 'Boleh berpecahan, maksimal 3 angka di belakang koma.' : 'Satuan ini hanya menerima bilangan bulat.'}
            readOnly={op.busy || op.pending}
          />
          <div className="flex flex-wrap gap-2">
            <button type="submit" className={btnPrimary} disabled={op.busy || op.pending || !online}>
              {op.busy ? 'Menyimpan...' : 'Simpan'}
            </button>
            <button type="button" className={btnSecondary} onClick={() => setEditing(false)} disabled={op.busy || op.pending}>
              Batal
            </button>
          </div>
        </form>
      ) : (
        <div className="flex flex-wrap gap-2 pt-1">
          <button type="button" className={btnSecondary} onClick={startEdit} disabled={blocked}>
            Ubah jumlah
          </button>
          <button type="button" className={btnSecondary} onClick={() => setConfirmDelete(true)} disabled={blocked}>
            Hapus
          </button>
          {canAttachPhoto ? (
            pendingPhoto ? (
              <button type="button" className={btnSecondary} onClick={() => void retryStoredPhoto()} disabled={blocked}>
                {photoBusy ? 'Mengunggah...' : 'Coba unggah foto lagi'}
              </button>
            ) : (
              <button type="button" className={btnSecondary} onClick={() => fileRef.current?.click()} disabled={blocked}>
                {photoBusy ? 'Memproses foto...' : 'Tambah foto'}
              </button>
            )
          ) : null}
        </div>
      )}
      <OpNotice error={op.error} pending={op.pending} busy={op.busy} onRetry={() => void op.retry()} onDiscard={op.discard} />
      {photoMsg ? (
        <p role="alert" className="text-sm text-red-900">
          {photoMsg}
        </p>
      ) : null}
      <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => void onPick(e)} />
      <ConfirmDialog
        open={confirmDelete}
        title="Hapus barang?"
        message={`Hapus "${row.name}" dari daftar kebutuhan? Anda dapat menambahkannya lagi nanti.`}
        confirmLabel="Hapus"
        cancelLabel="Batal"
        onConfirm={remove}
        onCancel={() => setConfirmDelete(false)}
      />
    </ListItemCard>
  )
}
EOF

# --- Terapkan patch (sudah lolos pengecekan di atas) ---
python3 "$PATCHPY"
rm -f "$PATCHPY"

echo "Selesai. Jalankan: npx vitest run src/features/daftar && npm run build"