import { useState } from 'react'
import { Link } from 'react-router-dom'
import { btnSecondary } from '../../components/ui'
import { ProductAdmin } from './ProductAdmin'
import { TaxonomyAdmin } from './TaxonomyAdmin'
import { useCatalog } from './useCatalog'
import { useOnline } from './useOnline'

const TABS = [
  { id: 'barang', label: 'Barang' },
  { id: 'kategori', label: 'Kategori' },
  { id: 'satuan', label: 'Satuan' },
] as const
type TabId = (typeof TABS)[number]['id']

export function AdminView({ workspaceId }: { workspaceId: string }) {
  const { data, loading, readError } = useCatalog(workspaceId)
  const online = useOnline()
  const [tab, setTab] = useState<TabId>('barang')

  return (
    <div className="w-full">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-slate-900">Kelola katalog</h1>
        <Link to="/katalog" className={btnSecondary}>
          Lihat katalog
        </Link>
      </div>

      {!online && (
        <p role="status" className="mt-3 text-sm text-slate-800">
          Offline. Mengubah katalog memerlukan koneksi internet, jadi formulir dinonaktifkan.
        </p>
      )}

      <div role="group" aria-label="Bagian katalog" className="mt-4 flex gap-2">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            aria-pressed={tab === t.id}
            onClick={() => setTab(t.id)}
            className={`min-h-11 flex-1 rounded-md border px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-900 focus-visible:ring-offset-2 sm:flex-none sm:px-6 ${
              tab === t.id
                ? 'border-slate-900 bg-slate-900 text-white'
                : 'border-slate-300 bg-white text-slate-900 hover:bg-slate-50'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="mt-6">
        {readError ? (
          <p role="alert" className="text-sm text-red-800">
            Katalog di perangkat tidak dapat dibaca: {readError}
          </p>
        ) : loading || !data ? (
          <p role="status" className="text-sm text-slate-700">
            Memuat katalog dari perangkat...
          </p>
        ) : tab === 'barang' ? (
          <ProductAdmin workspaceId={workspaceId} data={data} online={online} />
        ) : tab === 'kategori' ? (
          <TaxonomyAdmin kind="category" workspaceId={workspaceId} rows={data.categories} online={online} />
        ) : (
          <TaxonomyAdmin kind="unit" workspaceId={workspaceId} rows={data.units} online={online} />
        )}
      </div>
    </div>
  )
}
