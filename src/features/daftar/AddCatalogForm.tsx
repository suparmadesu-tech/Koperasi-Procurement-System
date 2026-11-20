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
