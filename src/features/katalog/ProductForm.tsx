import { useEffect, useState, type ChangeEvent, type FormEvent } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '../../components/ui'
import { createProduct, updateProduct } from './catalogWrite'
import { Field, FlashMessage, type Flash } from './formUi'
import { compressImage } from './photoCompress'
import { usePhotoUrl } from './photo'
import { uploadProductPhoto } from './photoUpload'
import { diffProduct } from './productDiff'
import { selectableOptions } from './search'
import type { CategoryRow, ProductRow, UnitRow } from './types'
import { validateProductForm } from './validation'

interface Prepared {
  blob: Blob
  mime: string
  url: string
}

type FieldErrors = Partial<Record<'name' | 'categoryId' | 'unitId' | 'price' | 'photo', string>>

function CurrentPhoto({ path, name }: { path: string | null; name: string }) {
  const { state, retry, reportImageError } = usePhotoUrl(path)
  if (state.kind === 'ready') {
    return (
      <img
        src={state.url}
        alt={name}
        width={160}
        height={120}
        onError={reportImageError}
        className="h-[120px] w-[160px] rounded-md bg-slate-100 object-contain"
      />
    )
  }
  const note =
    state.kind === 'none'
      ? 'Belum ada foto.'
      : state.kind === 'loading'
        ? 'Memuat foto...'
        : state.kind === 'offline'
          ? 'Foto tidak tersedia saat offline.'
          : 'Foto gagal dimuat.'
  return (
    <div className="flex items-center gap-3 text-sm text-slate-700">
      <span>{note}</span>
      {(state.kind === 'offline' || state.kind === 'error') && (
        <button type="button" onClick={retry} className={btnSecondary}>
          Coba lagi
        </button>
      )}
    </div>
  )
}

export function ProductForm({
  workspaceId,
  product,
  categories,
  units,
  online,
  onClose,
}: {
  workspaceId: string
  product: ProductRow | null
  categories: readonly CategoryRow[]
  units: readonly UnitRow[]
  online: boolean
  onClose: (message?: string) => void
}) {
  // Setelah INSERT berhasil, formulir beralih ke mode ubah agar percobaan ulang tidak membuat barang ganda.
  const [current, setCurrent] = useState<ProductRow | null>(product)
  const [name, setName] = useState(product?.name ?? '')
  const [categoryId, setCategoryId] = useState(product?.category_id ?? '')
  const [unitId, setUnitId] = useState(product?.unit_id ?? '')
  const [priceText, setPriceText] = useState(product?.price ?? '')
  const [archived, setArchived] = useState(product?.is_archived ?? false)
  const [photo, setPhoto] = useState<Prepared | null>(null)
  const [pendingPath, setPendingPath] = useState<string | null>(null)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [flash, setFlash] = useState<Flash>(null)
  const [busy, setBusy] = useState(false)
  const [preparing, setPreparing] = useState(false)

  useEffect(() => {
    if (!photo) return undefined
    return () => URL.revokeObjectURL(photo.url)
  }, [photo])

  const categoryOptions = selectableOptions(categories, product?.category_id)
  const unitOptions = selectableOptions(units, product?.unit_id)

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setPreparing(true)
    setErrors((prev) => ({ ...prev, photo: undefined }))
    const r = await compressImage(file)
    setPreparing(false)
    if (!r.ok) {
      setErrors((prev) => ({ ...prev, photo: r.error.message }))
      return
    }
    setPendingPath(null)
    setPhoto({ blob: r.data.blob, mime: r.data.mime, url: URL.createObjectURL(r.data.blob) })
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (busy || preparing) return
    const v = validateProductForm({ name, categoryId, unitId, priceText })
    if (!v.ok) {
      setErrors((prev) => ({ ...v.errors, photo: prev.photo }))
      setFlash(null)
      return
    }
    setErrors({})
    setFlash(null)
    setBusy(true)

    let saved = current
    let changed = false
    if (!saved) {
      const r = await createProduct(workspaceId, v.value)
      if (!r.ok) {
        setBusy(false)
        setFlash({ kind: 'error', text: r.error.message })
        return
      }
      saved = r.data
      changed = true
      setCurrent(saved)
    } else {
      const patch = diffProduct(saved, v.value, archived)
      if (Object.keys(patch).length > 0) {
        const r = await updateProduct(workspaceId, saved.id, patch)
        if (!r.ok) {
          setBusy(false)
          setFlash({ kind: 'error', text: r.error.message })
          return
        }
        saved = r.data
        changed = true
        setCurrent(saved)
      }
    }

    if (photo || pendingPath) {
      let path = pendingPath
      if (!path && photo) {
        const up = await uploadProductPhoto(workspaceId, photo.blob, photo.mime)
        if (!up.ok) {
          setBusy(false)
          setFlash({ kind: 'error', text: `Data barang tersimpan, tetapi foto gagal diunggah: ${up.error.message}` })
          return
        }
        path = up.data
        setPendingPath(path)
      }
      const r = await updateProduct(workspaceId, saved.id, { photoPath: path as string })
      if (!r.ok) {
        setBusy(false)
        setFlash({
          kind: 'error',
          text: `Foto sudah terunggah tetapi belum terpasang pada barang: ${r.error.message} Tekan Simpan lagi untuk memasangnya.`,
        })
        return
      }
      setCurrent(r.data)
      setPhoto(null)
      setPendingPath(null)
      changed = true
    }

    setBusy(false)
    onClose(changed ? 'Barang tersimpan.' : 'Tidak ada perubahan.')
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <h2 className="text-lg font-semibold text-slate-900">{product ? 'Ubah barang' : 'Tambah barang'}</h2>
      <fieldset disabled={!online || busy} className="space-y-4">
        <Field label="Nama barang" error={errors.name}>
          {(p) => (
            <input
              id={p.id}
              value={name}
              onChange={(e) => setName(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              autoComplete="off"
              className={inputClass}
            />
          )}
        </Field>
        <Field label="Kategori" error={errors.categoryId}>
          {(p) => (
            <select
              id={p.id}
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className={inputClass}
            >
              <option value="">Pilih kategori</option>
              {categoryOptions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                  {c.is_archived ? ' (Diarsipkan)' : ''}
                </option>
              ))}
            </select>
          )}
        </Field>
        <Field label="Satuan" error={errors.unitId}>
          {(p) => (
            <select
              id={p.id}
              value={unitId}
              onChange={(e) => setUnitId(e.target.value)}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className={inputClass}
            >
              <option value="">Pilih satuan</option>
              {unitOptions.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name}
                  {u.is_archived ? ' (Diarsipkan)' : ''}
                </option>
              ))}
            </select>
          )}
        </Field>
        <Field
          label="Harga satuan (Rupiah, opsional)"
          error={errors.price}
          hint="Kosongkan bila harga belum diketahui. Harga 0 dianggap harga."
        >
          {(p) => (
            <input
              id={p.id}
              value={priceText}
              onChange={(e) => setPriceText(e.target.value)}
              inputMode="numeric"
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              autoComplete="off"
              className={inputClass}
            />
          )}
        </Field>

        <Field
          label="Foto (opsional)"
          error={errors.photo}
          hint="Dikompres otomatis di perangkat menjadi sekitar 200 KB."
        >
          {(p) => (
            <input
              id={p.id}
              type="file"
              accept="image/*"
              onChange={onPick}
              disabled={preparing}
              aria-invalid={p.invalid}
              aria-describedby={p.describedBy}
              className="block w-full text-sm text-slate-800 file:mr-3 file:min-h-11 file:rounded-md file:border file:border-slate-300 file:bg-white file:px-4 file:text-slate-900"
            />
          )}
        </Field>
        <div aria-live="polite">
          {preparing && <p className="text-sm text-slate-700">Memproses foto...</p>}
          {photo ? (
            <div className="flex items-end gap-3">
              <img
                src={photo.url}
                alt="Foto baru yang akan disimpan"
                width={160}
                height={120}
                className="h-[120px] w-[160px] rounded-md bg-slate-100 object-contain"
              />
              <div className="text-sm text-slate-700">
                <p>{Math.round(photo.blob.size / 1024)} KB, belum disimpan.</p>
                <button type="button" onClick={() => setPhoto(null)} className={`${btnSecondary} mt-2`}>
                  Batal pilih foto
                </button>
              </div>
            </div>
          ) : (
            current && <CurrentPhoto path={current.photo_path} name={current.name} />
          )}
        </div>

        {product && (
          <label className="flex min-h-11 items-center gap-3 text-sm text-slate-900">
            <input
              type="checkbox"
              checked={archived}
              onChange={(e) => setArchived(e.target.checked)}
              className="h-5 w-5"
            />
            Diarsipkan (tidak muncul untuk penambahan baru)
          </label>
        )}
      </fieldset>

      {!online && (
        <p role="status" className="text-sm text-slate-700">
          Offline. Perubahan katalog memerlukan koneksi internet.
        </p>
      )}
      <FlashMessage flash={flash} />
      <div className="flex gap-3">
        <button type="submit" disabled={!online || busy || preparing} className={`${btnPrimary} flex-1 sm:flex-none`}>
          {busy ? 'Menyimpan...' : 'Simpan'}
        </button>
        <button type="button" disabled={busy} onClick={() => onClose()} className={`${btnSecondary} flex-1 sm:flex-none`}>
          {current && !product ? 'Selesai' : 'Batal'}
        </button>
      </div>
    </form>
  )
}
