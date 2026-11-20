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
