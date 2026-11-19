import { useEffect, useMemo, useState } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '../../components/ui'
import { Field, FlashMessage, type Flash } from './formUi'
import { ProductForm } from './ProductForm'
import { filterProducts, indexById, selectableOptions } from './search'
import type { CatalogData, ProductRow } from './types'
import { describeProduct, pageSlice, PAGE_STEP } from './viewModel'

export function ProductAdmin({
  workspaceId,
  data,
  online,
}: {
  workspaceId: string
  data: CatalogData
  online: boolean
}) {
  const [editing, setEditing] = useState<{ product: ProductRow | null } | null>(null)
  const [query, setQuery] = useState('')
  const [limit, setLimit] = useState(PAGE_STEP)
  const [flash, setFlash] = useState<Flash>(null)

  const categories = useMemo(() => indexById(data.categories), [data.categories])
  const units = useMemo(() => indexById(data.units), [data.units])
  const filtered = useMemo(() => filterProducts(data.products, { query, archive: 'all' }), [data.products, query])
  const { shown, remaining } = pageSlice(filtered, limit)
  const canAdd = selectableOptions(data.categories).length > 0 && selectableOptions(data.units).length > 0

  useEffect(() => {
    setLimit(PAGE_STEP)
  }, [query])

  if (editing) {
    return (
      <ProductForm
        key={editing.product?.id ?? 'baru'}
        workspaceId={workspaceId}
        product={editing.product}
        categories={data.categories}
        units={data.units}
        online={online}
        onClose={(message) => {
          setEditing(null)
          if (message) setFlash({ kind: 'ok', text: message })
        }}
      />
    )
  }

  return (
    <section aria-label="Barang" className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-0 flex-1 basis-56">
          <Field label="Cari barang">
            {(p) => (
              <input
                id={p.id}
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                autoComplete="off"
                className={inputClass}
              />
            )}
          </Field>
        </div>
        <button
          type="button"
          disabled={!online || !canAdd}
          onClick={() => {
            setFlash(null)
            setEditing({ product: null })
          }}
          className={btnPrimary}
        >
          Tambah barang
        </button>
      </div>
      {!canAdd && (
        <p className="text-sm text-slate-700">
          Buat minimal satu kategori dan satu satuan aktif sebelum menambah barang.
        </p>
      )}
      <FlashMessage flash={flash} />

      {data.products.length === 0 ? (
        <p className="text-sm text-slate-700">Belum ada barang di katalog.</p>
      ) : filtered.length === 0 ? (
        <p className="text-sm text-slate-900">Tidak ada barang yang cocok dengan pencarian ini.</p>
      ) : (
        <>
          <p aria-live="polite" className="text-sm text-slate-700">
            {filtered.length} barang
          </p>
          <ul className="divide-y divide-slate-200 border-y border-slate-200">
            {shown.map((p) => {
              const v = describeProduct(p, categories, units)
              return (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setFlash(null)
                      setEditing({ product: p })
                    }}
                    className="flex min-h-14 w-full items-start justify-between gap-3 px-1 py-3 text-left hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-slate-900"
                  >
                    <span className="min-w-0">
                      <span className="block break-words font-medium text-slate-900">{p.name}</span>
                      <span className="block break-words text-sm text-slate-600">
                        {v.categoryName} / {v.unitName}
                      </span>
                      {p.is_archived && (
                        <span className="mt-1 inline-block rounded-sm border border-slate-500 px-1.5 text-xs text-slate-800">
                          Diarsipkan
                        </span>
                      )}
                    </span>
                    <span className="max-w-[8rem] shrink-0 text-right text-sm tabular-nums text-slate-700">
                      {v.priceText ?? 'Harga belum tersedia'}
                    </span>
                  </button>
                </li>
              )
            })}
          </ul>
          {remaining > 0 && (
            <button type="button" onClick={() => setLimit((n) => n + PAGE_STEP)} className={`${btnSecondary} w-full`}>
              Tampilkan {Math.min(PAGE_STEP, remaining)} lagi (sisa {remaining})
            </button>
          )}
        </>
      )}
    </section>
  )
}
