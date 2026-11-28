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
