import { useSyncExternalStore } from 'react'

export interface PendingPhoto {
  blob: Blob
  mime: string
}

// Hanya di memori: hilang bila halaman dimuat ulang. Tahap 6 memindahkannya ke antrean offline.
const store = new Map<string, PendingPhoto>()
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export function setPendingPhoto(itemId: string, photo: PendingPhoto): void {
  store.set(itemId, photo)
  emit()
}

export function clearPendingPhoto(itemId: string): void {
  if (store.delete(itemId)) emit()
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function usePendingPhoto(itemId: string): PendingPhoto | undefined {
  return useSyncExternalStore(subscribe, () => store.get(itemId), () => undefined)
}
