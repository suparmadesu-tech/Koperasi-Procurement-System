import { useMemo } from 'react'
import type { SubmitOptions } from '../daftar/submitCore'
import { isOnline } from '../katalog/catalogStore'
import { createBulkBatch } from './bulkBatch'
import { createItemOps } from './itemOps'
import type { SessionOpType } from './sessionRpc'
import { requestSessionRefresh } from './sessionSync'
import { submitSessionOp } from './submitSessionOp'

// Menghubungkan pengendali murni dengan titik tunggal penulisan sesi. Tidak ada pola kirim baru.
export function useChecklist(workspaceId: string) {
  return useMemo(() => {
    const common = {
      submit: (type: SessionOpType, payload: Record<string, unknown>, options: SubmitOptions) =>
        submitSessionOp(workspaceId, type, payload, options),
      newId: () => crypto.randomUUID(),
      isOnline,
      // Percobaan dihentikan: hasilnya tidak diketahui, jadi layar disegarkan dari server.
      onDiscard: requestSessionRefresh,
    }
    return { items: createItemOps(common), bulk: createBulkBatch(common) }
  }, [workspaceId])
}

export type Checklist = ReturnType<typeof useChecklist>
