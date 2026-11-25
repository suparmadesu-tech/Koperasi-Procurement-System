import type { ReactNode } from 'react'
import { formatRupiah } from '../../lib/money'
import { formatQuantity } from '../daftar/format'
import { ItemPhoto } from '../daftar/ListItemCard'
import type { SessionItemView } from './sessionView'

export function SessionItemCard({
  item,
  photoUrl,
  children,
}: {
  item: SessionItemView
  photoUrl: string | undefined
  children?: ReactNode
}) {
  const unit = item.unitName ? ` ${item.unitName}` : ''
  return (
    <li className="flex gap-3 rounded-md bg-white p-3 ring-1 ring-black/20">
      {item.photoPath ? <ItemPhoto key={photoUrl ?? 'tanpa-url'} url={photoUrl} name={item.name} /> : null}
      <div className="min-w-0 flex-1 space-y-1">
        <p className="break-words font-semibold">{item.name}</p>
        <p className="text-sm">
          Dibutuhkan {formatQuantity(item.needed)}
          {unit}
          {item.actual !== null ? ` · Aktual ${formatQuantity(item.actual)}${unit}` : ''}
        </p>
        {item.note ? <p className="whitespace-pre-line break-words text-sm">Catatan: {item.note}</p> : null}
        {item.price === null ? (
          <p className="text-sm">Harga belum tersedia</p>
        ) : (
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
            <span>
              {formatRupiah(item.price)} {item.priceIsActual ? '(harga aktual)' : '(harga awal sesi)'}
            </span>
            {item.subtotal !== null ? (
              <span className="font-semibold">{formatRupiah(item.subtotal)}</span>
            ) : (
              <span className="text-xs text-ink/75">Belum masuk total</span>
            )}
          </div>
        )}
        {item.direct ? <p className="text-xs text-ink/75">Ditambahkan langsung ke sesi</p> : null}
        {children}
      </div>
    </li>
  )
}
