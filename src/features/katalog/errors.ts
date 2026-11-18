import type { CatalogError } from './types'

export interface RawWriteError {
  code?: string
  message?: string
  details?: string
}

const MESSAGES: Record<string, string> = {
  OFFLINE: 'Mengubah katalog memerlukan koneksi internet. Sambungkan perangkat, lalu coba lagi.',
  AUTH_EXPIRED: 'Sesi login berakhir. Masuk kembali, lalu coba lagi.',
  KPS_FORBIDDEN: 'Anda tidak berhak melakukan perubahan ini.',
  KPS_CONFLICT: 'Data yang sama sudah ada.',
  KPS_REFERENCE_INVALID: 'Data yang dirujuk tidak ditemukan.',
  KPS_REF_ARCHIVED: 'Kategori atau satuan yang dipilih sudah diarsipkan.',
  KPS_INVALID_PRICE: 'Harga harus Rupiah bulat dan tidak negatif.',
  KPS_TEXT_TOO_LONG: 'Teks melebihi batas panjang yang diizinkan.',
  KPS_INVALID_PHOTO_PATH: 'Alamat foto tidak sesuai format.',
  KPS_INVALID_INPUT: 'Isian tidak valid.',
  KPS_CHECK_VIOLATION: 'Isian melanggar aturan data.',
  UNKNOWN: 'Perubahan gagal disimpan. Coba lagi beberapa saat.',
}

const NETWORK = /failed to fetch|networkerror|load failed|network request failed/i

const err = (code: string, message?: string): CatalogError => ({ code, message: message ?? MESSAGES[code] ?? MESSAGES.UNKNOWN })

// Pemetaan SQLSTATE dan nama constraint untuk penulisan langsung (Bagian 3, 7.2 dan 8).
export function mapWriteError(e: RawWriteError | null | undefined): CatalogError {
  const code = e?.code ?? ''
  const text = `${e?.message ?? ''} ${e?.details ?? ''}`

  if (!code && NETWORK.test(text)) return err('OFFLINE')
  if (code === 'PGRST301' || /jwt expired/i.test(text)) return err('AUTH_EXPIRED')

  const kps = /\bKPS_[A-Z_]+\b/.exec(e?.message ?? '')
  if (kps) return err(kps[0])

  if (code === '42501') return err('KPS_FORBIDDEN')
  if (code === '23503') return err('KPS_REFERENCE_INVALID')
  if (code === '23505') {
    if (/categories_name_active_uq/.test(text)) return err('KPS_CONFLICT', 'Nama kategori sudah dipakai kategori lain yang aktif.')
    if (/units_name_active_uq/.test(text)) return err('KPS_CONFLICT', 'Nama satuan sudah dipakai satuan lain yang aktif.')
    return err('KPS_CONFLICT')
  }
  if (code === '23514') {
    if (/kps_rupiah_check/.test(text)) return err('KPS_INVALID_PRICE')
    if (/(products|categories|units)_name_len_chk/.test(text)) return err('KPS_TEXT_TOO_LONG')
    if (/products_photo_path_fmt_chk/.test(text)) return err('KPS_INVALID_PHOTO_PATH')
    return err('KPS_CHECK_VIOLATION')
  }
  if (code.startsWith('22')) return err('KPS_INVALID_INPUT')
  return err('UNKNOWN')
}
