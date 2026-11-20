import type { SendError } from '../../lib/sync-errors'

const MESSAGES: Record<string, string> = {
  KPS_FORBIDDEN: 'Akun Anda tidak berhak melakukan perubahan ini.',
  KPS_INVALID_INPUT: 'Data yang dikirim tidak valid.',
  KPS_UNKNOWN_OP: 'Jenis perubahan tidak dikenali server.',
  KPS_OP_ID_CONFLICT: 'Perubahan ini bentrok dengan perubahan lain. Muat ulang lalu coba lagi.',
  KPS_INTERNAL: 'Server sedang bermasalah. Coba lagi sebentar lagi.',
  KPS_DEPENDENCY_MISSING: 'Perubahan sebelumnya belum diproses server. Coba lagi.',
  KPS_DEPENDENCY_REJECTED: 'Perubahan sebelumnya ditolak, jadi perubahan ini tidak dikirim.',
  KPS_TARGET_NOT_FOUND: 'Barang tidak ditemukan. Mungkin sudah dihapus atau dipindahkan.',
  KPS_ITEM_DELETED: 'Barang ini sudah dihapus. Tambahkan lagi bila masih diperlukan.',
  KPS_ITEM_MOVED: 'Barang ini sudah dipindahkan ke sesi belanja, jadi tidak dapat diubah dari daftar.',
  KPS_PRODUCT_ARCHIVED: 'Barang ini sudah diarsipkan dan tidak dapat ditambahkan lagi.',
  KPS_FRACTION_NOT_ALLOWED: 'Satuan barang ini tidak menerima jumlah berpecahan.',
  KPS_INVALID_QUANTITY: 'Jumlah harus lebih dari 0 dan paling banyak 3 angka di belakang koma.',
  KPS_TEXT_TOO_LONG: 'Teks terlalu panjang. Nama maksimal 200 karakter, satuan 50, catatan 1000.',
  KPS_CONFLICT: 'Data ini sudah ada. Muat ulang lalu coba lagi.',
  KPS_PHOTO_NOT_FOUND: 'Berkas foto belum ada di penyimpanan. Unggah ulang fotonya.',
  KPS_INVALID_PHOTO_PATH: 'Lokasi foto tidak valid.',
  KPS_INVALID_ITEM_KIND: 'Perubahan ini tidak berlaku untuk jenis barang tersebut.',
  KPS_REFERENCE_INVALID: 'Data yang dirujuk tidak ditemukan.',
  KPS_CHECK_VIOLATION: 'Data tidak memenuhi aturan penyimpanan.',
}

const GENERIC_REJECTED = 'Perubahan ditolak server.'

export function messageForCode(code: string | null | undefined, serverMessage?: string): string {
  if (code) {
    const known = MESSAGES[code]
    if (known) return known
  }
  const fromServer = serverMessage?.trim()
  return fromServer ? fromServer : GENERIC_REJECTED
}

export function messageForSendError(e: SendError): string {
  if (e.network) return 'Tidak dapat terhubung ke server. Periksa koneksi, lalu coba lagi.'
  if (e.kpsCode) return messageForCode(e.kpsCode)
  if (e.sqlState === '42501' || e.httpStatus === 401 || e.httpStatus === 403) {
    return 'Akses ditolak. Keluar lalu masuk kembali bila terus berulang.'
  }
  return 'Server sedang bermasalah. Coba lagi sebentar lagi.'
}
