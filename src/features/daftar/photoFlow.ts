import type { CompressedPhoto } from '../katalog/photoCompress'
import type { Result } from '../katalog/types'

export interface PhotoFlowDeps {
  compress: (file: File) => Promise<Result<CompressedPhoto>>
  upload: (workspaceId: string, blob: Blob, mime: string) => Promise<Result<string>>
}

export type PhotoPrep =
  | { kind: 'none' }
  | { kind: 'ready'; path: string; blob: Blob; mime: string }
  | { kind: 'upload_failed'; blob: Blob; mime: string; message: string }
  | { kind: 'invalid'; message: string }

// Unggah ke path baru lebih dulu; kegagalan unggah tidak membatalkan barangnya (FR-013, SYNC-019).
export async function uploadPrepared(
  deps: PhotoFlowDeps,
  workspaceId: string,
  blob: Blob,
  mime: string,
): Promise<PhotoPrep> {
  const up = await deps.upload(workspaceId, blob, mime)
  if (!up.ok) return { kind: 'upload_failed', blob, mime, message: up.error.message }
  return { kind: 'ready', path: up.data, blob, mime }
}

export async function preparePhoto(deps: PhotoFlowDeps, workspaceId: string, file: File | null): Promise<PhotoPrep> {
  if (!file) return { kind: 'none' }
  const c = await deps.compress(file)
  if (!c.ok) return { kind: 'invalid', message: c.error.message }
  return uploadPrepared(deps, workspaceId, c.data.blob, c.data.mime)
}
