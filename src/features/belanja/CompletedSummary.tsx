import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'
import { formatDateTimeJakarta } from './format'
import type { CompletedView } from './sessionView'

export function CompletedSummary({ view }: { view: CompletedView }) {
  const { estimate } = view
  return (
    <section aria-labelledby="ringkasan-selesai" className="space-y-4 rounded-md bg-white p-4 ring-1 ring-black/20">
      <div>
        <h2 id="ringkasan-selesai" className="font-semibold">
          Sesi belanja terakhir selesai
        </h2>
        {view.endedAt ? <p className="text-sm text-ink/75">Selesai {formatDateTimeJakarta(view.endedAt)} WIB</p> : null}
      </div>
      <dl className="space-y-4">
        <div className="space-y-1">
          <dt className="text-sm text-ink/75">Total aktual (barang yang dibeli)</dt>
          <dd className="text-2xl font-semibold">
            {view.totalActual === null ? 'Tidak tersedia' : formatRupiah(view.totalActual)}
          </dd>
          {view.unpricedPurchased === null ? (
            <dd className="text-sm">Jumlah barang tanpa harga tidak tersedia.</dd>
          ) : view.unpricedPurchased > 0 ? (
            <dd className="text-sm">{unpricedLabel(view.unpricedPurchased)}.</dd>
          ) : null}
        </div>
        <div className="space-y-1">
          <dt className="text-sm text-ink/75">Estimasi awal (saat sesi dimulai)</dt>
          <dd className="text-lg font-semibold">
            {estimate.total === null ? 'Tidak tersedia' : formatRupiah(estimate.total)}
          </dd>
          {estimate.unpricedCount !== null && estimate.unpricedCount > 0 ? (
            <dd className="text-sm">{unpricedLabel(estimate.unpricedCount)}.</dd>
          ) : null}
        </div>
      </dl>
      <p className="text-sm">
        {view.purchasedCount} barang dibeli. {view.returnCount} barang memiliki sisa yang dikembalikan ke daftar
        kebutuhan.
      </p>
    </section>
  )
}
