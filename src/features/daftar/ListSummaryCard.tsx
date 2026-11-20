import { formatRupiah } from '../../lib/money'
import { unpricedLabel, type ListSummary } from './listView'

export function ListSummaryCard({ summary }: { summary: ListSummary }) {
  return (
    <section aria-labelledby="ringkasan-estimasi" className="rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="ringkasan-estimasi" className="text-sm text-ink/75">
        Estimasi total
      </h2>
      <p className="text-2xl font-semibold">{formatRupiah(summary.total)}</p>
      <p className="text-sm">{summary.itemCount} barang</p>
      {summary.incomplete ? (
        <div className="mt-2 text-sm">
          <p className="font-semibold">Estimasi belum lengkap</p>
          <p>{unpricedLabel(summary.unpricedCount)}.</p>
        </div>
      ) : null}
      <p className="mt-2 text-xs text-ink/75">Memakai harga katalog saat ini, bukan harga saat belanja.</p>
    </section>
  )
}
