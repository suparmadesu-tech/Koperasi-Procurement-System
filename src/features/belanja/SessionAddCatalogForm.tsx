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
