import { useMemo, useSyncExternalStore } from 'react'
import { photoDeps } from '../daftar/photoDeps'
import { isOnline } from '../katalog/catalogStore'
import { setFlowNotice } from './flowNotice'
import { createSessionAdd, isSessionLevelCode } from './sessionAdd'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

// Menghubungkan pengendali murni dengan titik tunggal penulisan sesi dan alur foto Tahap 3. Tidak ada pola baru.
export function useAddToSession(workspaceId: string, sessionId: string) {
  const add = useMemo(
    () =>
      createSessionAdd({
        workspaceId,
        sessionId,
        submit: (type, payload, options) => submitSessionOp(workspaceId, type, payload, options),
        newId: () => crypto.randomUUID(),
        newItemId: () => crypto.randomUUID(),
        isOnline,
        photo: photoDeps,
        // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
        onDiscard: requestSessionRefresh,
        // Sesi sudah berakhir: layar berpindah, jadi pesan dibawa ke spanduk halaman.
        onSettled: (o) => {
          if (!o.ok && o.failure.kind === 'rejected' && isSessionLevelCode(o.failure.code)) {
            setFlowNotice({ tone: 'error', text: o.failure.message })
          }
        },
      }),
    [workspaceId, sessionId],
  )
  const state = useSyncExternalStore(add.subscribe, add.getState, add.getState)
  return { add, state }
}
