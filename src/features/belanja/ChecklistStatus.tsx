import { useSyncExternalStore } from 'react'
import type { Checklist } from './useChecklist'

// Satu region status untuk seluruh daftar: hasil terakhir yang dikonfirmasi server dan alasan kontrol nonaktif.
export function ChecklistStatus({ checklist, online }: { checklist: Checklist; online: boolean }) {
  const { getLast, subscribe } = checklist.items
  const last = useSyncExternalStore(subscribe, getLast, getLast)
  if (online && last === null) return null
  return (
    <div className="space-y-1">
      {!online ? (
        <p role="status" className="text-sm">
          Anda sedang offline. Mengubah status, jumlah aktual, dan harga aktual memerlukan koneksi internet.
        </p>
      ) : null}
      {last ? (
        <p role="status" className="text-sm">
          {last.text}
        </p>
      ) : null}
    </div>
  )
}
