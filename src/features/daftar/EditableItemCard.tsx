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
