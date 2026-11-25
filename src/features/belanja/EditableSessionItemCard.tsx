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
