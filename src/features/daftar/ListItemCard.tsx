import { useState, type ReactNode } from 'react'
import { formatRupiah } from '../../lib/money'
import type { SyncStatus } from '../katalog/catalogSync'
import { formatQuantity } from './format'
import type { ListViewRow } from './listView'

function ItemPhoto({ url, name }: { url: string | undefined; name: string }) {
  const [failed, setFailed] = useState(false)
  if (!url || failed) {
    return (
      <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-md bg-black/5 p-1 text-center text-xs text-ink/75">
        Foto belum termuat
      </div>
    )
  }
  return (
    <img
      src={url}
      alt={name}
      width={64}
      height={64}
      loading="lazy"
      decoding="async"
      onError={() => setFailed(true)}
      className="h-16 w-16 shrink-0 rounded-md object-cover"
    />
  )
}

export function ListItemCard({
  row,
  photoUrl,
  catalogStatus,
  children,
}: {
  row: ListViewRow
  photoUrl: string | undefined
  catalogStatus: SyncStatus
  children?: ReactNode
}) {
  return (
    <li className="flex gap-3 rounded-md bg-white p-3 ring-1 ring-black/20">
      {row.photoPath ? <ItemPhoto key={photoUrl ?? 'tanpa-url'} url={photoUrl} name={row.name} /> : null}
      <div className="min-w-0 flex-1 space-y-1">
        <p className="break-words font-semibold">{row.name}</p>
        <p className="text-sm">
          {formatQuantity(row.quantity)}
          {row.unitName ? ` ${row.unitName}` : ''}
          {row.archived ? <span className="ml-2 rounded-sm px-1.5 py-0.5 text-xs ring-1 ring-black/40">Diarsipkan</span> : null}
        </p>
        {row.note ? <p className="whitespace-pre-line break-words text-sm">Catatan: {row.note}</p> : null}
        {row.unresolved ? (
          <p className="text-xs text-ink/75">
            {catalogStatus === 'ok'
              ? 'Produk ini tidak ada di katalog.'
              : 'Katalog belum termuat; nama dan harga menyusul.'}
          </p>
        ) : null}
        {row.price !== null && row.subtotal !== null ? (
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
            <span>
              {formatRupiah(row.price)} × {formatQuantity(row.quantity)}
            </span>
            <span className="font-semibold">{formatRupiah(row.subtotal)}</span>
          </div>
        ) : (
          <p className="text-sm">Harga belum tersedia</p>
        )}
        {children}
      </div>
    </li>
  )
}
