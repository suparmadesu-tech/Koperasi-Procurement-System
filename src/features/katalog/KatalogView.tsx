import { useDeferredValue, useEffect, useId, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { btnSecondary, inputClass } from '../../components/ui'
import { ProductSheet } from './ProductSheet'
import { compareByName, filterProducts, indexById, type ArchiveFilter } from './search'
import { useCatalog } from './useCatalog'
import { describeProduct, formatClock, pageSlice, PAGE_STEP } from './viewModel'

const labelClass = 'mb-1 block text-sm font-medium text-slate-800'
const rowFocus = 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-slate-900'

export function KatalogView({ workspaceId, isAdmin }: { workspaceId: string; isAdmin: boolean }) {
  const { data, loading, readError, sync, refresh } = useCatalog(workspaceId)
  const [query, setQuery] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [archive, setArchive] = useState<ArchiveFilter>('active')
  const [limit, setLimit] = useState(PAGE_STEP)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const deferredQuery = useDeferredValue(query)
  const queryId = useId()
  const categoryFieldId = useId()
  const archiveId = useId()

  const categories = useMemo(() => indexById(data?.categories ?? []), [data])
  const units = useMemo(() => indexById(data?.units ?? []), [data])
  const categoryOptions = useMemo(
    () => [...(data?.categories ?? [])].sort(compareByName),
    [data],
  )
  const filtered = useMemo(
    () =>
      filterProducts(data?.products ?? [], {
        query: deferredQuery,
        categoryId: categoryId || null,
        archive,
      }),
    [data, deferredQuery, categoryId, archive],
  )
  const { shown, remaining } = pageSlice(filtered, limit)
  const selected = selectedId ? (data?.products.find((p) => p.id === selectedId) ?? null) : null

  useEffect(() => {
    setLimit(PAGE_STEP)
  }, [deferredQuery, categoryId, archive])

  const hasFilter = query !== '' || categoryId !== '' || archive !== 'active'
  const resetFilters = () => {
    setQuery('')
    setCategoryId('')
    setArchive('active')
  }

  const total = data?.products.length ?? 0

  return (
    <div className="w-full">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-slate-900">Katalog</h1>
        {isAdmin && (
          <Link to="/pengaturan/admin" className={btnSecondary}>
            Kelola katalog
          </Link>
        )}
      </div>

      <SyncLine state={sync} onRetry={refresh} />

      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)]">
        <div className="col-span-2 sm:col-span-1">
          <label htmlFor={queryId} className={labelClass}>
            Cari barang
          </label>
          <input
            id={queryId}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            autoComplete="off"
            className={inputClass}
          />
        </div>
        <div>
          <label htmlFor={categoryFieldId} className={labelClass}>
            Kategori
          </label>
          <select
            id={categoryFieldId}
            value={categoryId}
            onChange={(e) => setCategoryId(e.target.value)}
            className={inputClass}
          >
            <option value="">Semua</option>
            {categoryOptions.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
                {c.is_archived ? ' (Diarsipkan)' : ''}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={archiveId} className={labelClass}>
            Status
          </label>
          <select
            id={archiveId}
            value={archive}
            onChange={(e) => setArchive(e.target.value as ArchiveFilter)}
            className={inputClass}
          >
            <option value="active">Aktif</option>
            <option value="archived">Diarsipkan</option>
            <option value="all">Semua</option>
          </select>
        </div>
      </div>

      <div className="mt-6">
        {readError ? (
          <p role="alert" className="text-sm text-red-800">
            Katalog di perangkat tidak dapat dibaca: {readError}
          </p>
        ) : loading ? (
          <p role="status" className="text-sm text-slate-700">
            Memuat katalog dari perangkat...
          </p>
        ) : total === 0 ? (
          <EmptyCatalog status={sync.status} isAdmin={isAdmin} />
        ) : filtered.length === 0 ? (
          <div className="rounded-md border border-slate-300 p-4">
            <p className="text-sm text-slate-900">Tidak ada barang yang cocok dengan pencarian ini.</p>
            {hasFilter && (
              <button type="button" onClick={resetFilters} className={`${btnSecondary} mt-3`}>
                Atur ulang pencarian
              </button>
            )}
          </div>
        ) : (
          <>
            <p aria-live="polite" className="mb-2 text-sm text-slate-700">
              {filtered.length} barang
            </p>
            <ul className="divide-y divide-slate-200 border-y border-slate-200 bg-white">
              {shown.map((p) => {
                const v = describeProduct(p, categories, units)
                return (
                  <li key={p.id}>
                    <button
                      type="button"
                      onClick={() => setSelectedId(p.id)}
                      className={`flex min-h-14 w-full items-start justify-between gap-3 px-4 py-3 text-left hover:bg-slate-50 ${rowFocus}`}
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
              <button
                type="button"
                onClick={() => setLimit((n) => n + PAGE_STEP)}
                className={`${btnSecondary} mt-4 w-full`}
              >
                Tampilkan {Math.min(PAGE_STEP, remaining)} lagi (sisa {remaining})
              </button>
            )}
          </>
        )}
      </div>

      {selected && (
        <ProductSheet
          product={selected}
          view={describeProduct(selected, categories, units)}
          onClose={() => setSelectedId(null)}
        />
      )}
    </div>
  )
}

function SyncLine({
  state,
  onRetry,
}: {
  state: ReturnType<typeof useCatalog>['sync']
  onRetry: () => void
}) {
  if (state.status === 'error') {
    return (
      <div role="alert" className="mt-2 flex flex-wrap items-center gap-3 text-sm text-red-800">
        <span>Gagal menyegarkan katalog: {state.error}</span>
        <button type="button" onClick={onRetry} className={btnSecondary}>
          Coba lagi
        </button>
      </div>
    )
  }
  const text =
    state.status === 'offline'
      ? 'Offline. Menampilkan data yang tersimpan di perangkat.'
      : state.status === 'syncing'
        ? 'Menyegarkan dari server...'
        : state.status === 'ok' && state.lastSyncedAt
          ? `Diperbarui pukul ${formatClock(state.lastSyncedAt)}.`
          : ''
  return (
    <p role="status" className="mt-2 min-h-5 text-sm text-slate-700">
      {text}
    </p>
  )
}

function EmptyCatalog({ status, isAdmin }: { status: string; isAdmin: boolean }) {
  if (status === 'idle' || status === 'syncing') {
    return (
      <p role="status" className="text-sm text-slate-700">
        Mengambil katalog dari server...
      </p>
    )
  }
  if (status === 'offline') {
    return (
      <p className="text-sm text-slate-900">
        Belum ada data katalog di perangkat. Sambungkan ke internet untuk mengambilnya.
      </p>
    )
  }
  if (status === 'error') {
    return <p className="text-sm text-slate-900">Katalog belum dapat diambil dari server.</p>
  }
  return (
    <div className="rounded-md border border-slate-300 p-4 text-sm text-slate-900">
      {isAdmin ? (
        <>
          <p>Katalog masih kosong.</p>
          <Link to="/pengaturan/admin" className={`${btnSecondary} mt-3 inline-block`}>
            Tambah barang
          </Link>
        </>
      ) : (
        <p>Katalog masih kosong. Admin belum menambahkan barang.</p>
      )}
    </div>
  )
}
