import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'
import { useOnline } from '../daftar/useOnline'
import { formatDateTimeJakarta } from './format'
import { SessionActions } from './SessionActions'
import { AddToSession } from './AddToSession'
import { BulkPurchase } from './BulkPurchase'
import { ChecklistStatus } from './ChecklistStatus'
import { EditableSessionItemCard } from './EditableSessionItemCard'
import type { ActiveView } from './sessionView'
import type { SessionItemRow } from './types'
import { useChecklist } from './useChecklist'

export function ActiveSession({
  view,
  photoUrls,
  workspaceId,
  sessionId,
  items,
}: {
  view: ActiveView
  photoUrls: Record<string, string>
  workspaceId: string
  sessionId: string
  items: SessionItemRow[]
}) {
  const online = useOnline()
  const checklist = useChecklist(workspaceId)
  const inCart = (view.groups.find((g) => g.status === 'in_cart')?.items ?? []).map((i) => ({
    id: i.id,
    name: i.name,
  }))
  const { running, frozen } = view
  const runningEmpty = running.pricedCount + running.unpricedCount === 0
  return (
    <div className="space-y-4">
      <section aria-labelledby="ringkasan-sesi" className="space-y-4 rounded-md bg-white p-4 ring-1 ring-black/20">
        <div>
          <h2 id="ringkasan-sesi" className="font-semibold">
            Sesi belanja aktif
          </h2>
          <p className="text-sm text-ink/75">Dimulai {formatDateTimeJakarta(view.startedAt)} WIB</p>
        </div>
        <dl className="space-y-4">
          <div className="space-y-1">
            <dt className="text-sm text-ink/75">Total berjalan (barang di keranjang dan sudah dibeli)</dt>
            <dd className="text-2xl font-semibold">{formatRupiah(running.total)}</dd>
            {running.incomplete ? (
              <dd className="text-sm">
                <span className="font-semibold">Total berjalan belum lengkap.</span> {unpricedLabel(running.unpricedCount)}.
              </dd>
            ) : null}
            {runningEmpty ? <dd className="text-sm">Belum ada barang di keranjang.</dd> : null}
            <dd className="text-xs text-ink/75">Memakai harga aktual bila diisi, jika tidak harga awal sesi.</dd>
          </div>
          <div className="space-y-1">
            <dt className="text-sm text-ink/75">Estimasi awal (dibekukan saat sesi dimulai)</dt>
            <dd className="text-lg font-semibold">
              {frozen.total === null ? 'Belum tersedia' : formatRupiah(frozen.total)}
            </dd>
            {frozen.unpricedCount !== null && frozen.unpricedCount > 0 ? (
              <dd className="text-sm">{unpricedLabel(frozen.unpricedCount)}.</dd>
            ) : null}
            <dd className="text-xs text-ink/75">
              Tidak berubah walau harga katalog diperbarui atau barang ditambahkan ke sesi.
            </dd>
          </div>
        </dl>
      </section>

      <SessionActions workspaceId={workspaceId} sessionId={sessionId} items={items} />

      <ChecklistStatus checklist={checklist} online={online} />

      <BulkPurchase checklist={checklist} items={inCart} online={online} />

      <AddToSession workspaceId={workspaceId} sessionId={sessionId} online={online} />

      {view.itemCount === 0 ? (
        <p className="text-sm">Sesi ini belum memiliki barang.</p>
      ) : (
        view.groups.map((g) => (
          <section key={g.status} aria-labelledby={`grup-${g.status}`} className="space-y-3">
            <h2 id={`grup-${g.status}`} className="font-semibold">
              {g.label} ({g.items.length})
            </h2>
            <ul className="space-y-3">
              {g.items.map((i) => (
                <EditableSessionItemCard
                  key={i.id}
                  item={i}
                  photoUrl={i.photoPath ? photoUrls[i.photoPath] : undefined}
                  checklist={checklist}
                  online={online}
                />
              ))}
            </ul>
          </section>
        ))
      )}
    </div>
  )
}
