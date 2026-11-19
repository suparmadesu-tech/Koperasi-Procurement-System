import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'
import { isOnline } from './catalogStore'
import { describeUploadError, newPhotoPath } from './photoPlan'
import type { Result } from './types'

const BUCKET = 'kps-photos'
const sb = supabase as unknown as SupabaseClient | null

// Selalu path baru dan tanpa upsert: berkas yang dirujuk snapshot tidak boleh tertimpa (BR-027).
export async function uploadProductPhoto(workspaceId: string, blob: Blob, mime: string): Promise<Result<string>> {
  if (!isOnline()) {
    return { ok: false, error: { code: 'OFFLINE', message: 'Mengunggah foto memerlukan koneksi internet.' } }
  }
  if (!sb) {
    return { ok: false, error: { code: 'NO_CLIENT', message: 'Supabase belum dikonfigurasi.' } }
  }
  const path = newPhotoPath(workspaceId, mime)
  try {
    const { error } = await sb.storage
      .from(BUCKET)
      .upload(path, blob, { contentType: mime, upsert: false, cacheControl: '31536000' })
    if (error) {
      return {
        ok: false,
        error: { code: 'UPLOAD_FAILED', message: describeUploadError(error as { message?: string }) },
      }
    }
    return { ok: true, data: path }
  } catch (e) {
    return {
      ok: false,
      error: { code: 'UPLOAD_FAILED', message: describeUploadError(e as { message?: string }) },
    }
  }
}
