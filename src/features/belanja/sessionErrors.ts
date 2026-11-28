import { messageForCode } from '../daftar/errors'

// Kode khusus sesi. Kode lain jatuh ke tabel pesan daftar.
const SESSION_MESSAGES: Record<string, string> = {
  KPS_SESSION_ALREADY_ACTIVE: 'Sudah ada sesi belanja yang aktif. Muat ulang untuk melihatnya.',
  KPS_SESSION_NOT_ACTIVE:
    'Sesi ini sudah selesai atau dibatalkan, jadi tidak dapat diubah lagi. Perubahan Anda tidak tersimpan.',
  KPS_ITEM_DELETED: 'Barang ini sudah dihapus dari sesi.',
  KPS_TARGET_NOT_FOUND: 'Sesi atau barang tidak ditemukan. Muat ulang untuk melihat keadaan terbaru.',
  KPS_SNAPSHOT_IMMUTABLE:
    'Perubahan ini tidak diizinkan: data awal barang dari daftar tidak dapat diubah, jumlah kebutuhan dan penghapusan hanya untuk barang yang ditambahkan langsung ke sesi, dan foto hanya dapat dipasang sekali.',
  KPS_QUANTITY_ACTUAL_STATE: 'Jumlah aktual hanya dapat diisi untuk barang yang sudah masuk keranjang atau dibeli.',
  KPS_INVALID_PRICE: 'Harga harus Rupiah bulat dan tidak negatif.',
  KPS_SESSION_FROZEN: 'Sesi ini sudah selesai atau dibatalkan, jadi tidak dapat diubah lagi.',
  KPS_SOURCE_NOT_MOVED: 'Data sesi tidak konsisten. Muat ulang lalu coba lagi.',
  KPS_TOTAL_MISMATCH: 'Total sesi tidak cocok dengan hitungan server. Muat ulang lalu coba lagi.',
  // Menambah barang ke sesi (FR-052): wording khusus sesi.
  KPS_PRODUCT_ARCHIVED: 'Barang katalog ini sudah diarsipkan, jadi tidak dapat ditambahkan ke sesi.',
  KPS_FRACTION_NOT_ALLOWED: 'Satuan barang ini tidak menerima jumlah berpecahan. Masukkan bilangan bulat.',
  KPS_INVALID_QUANTITY: 'Jumlah harus lebih dari 0 dan paling banyak 3 angka di belakang koma.',
  KPS_TEXT_TOO_LONG: 'Teks terlalu panjang. Nama maksimal 200 karakter, satuan 50, catatan 1000.',
  KPS_CONFLICT: 'Barang dengan ID ini sudah ada di sesi. Muat ulang untuk melihatnya.',
  KPS_PHOTO_NOT_FOUND: 'Berkas foto belum ada di penyimpanan, jadi barang belum ditambahkan. Coba lagi atau tambahkan tanpa foto.',
  KPS_INVALID_PHOTO_PATH: 'Lokasi foto tidak valid, jadi barang belum ditambahkan. Coba lagi atau tambahkan tanpa foto.',
}

export function sessionMessageForCode(code: string | null | undefined, serverMessage?: string): string {
  if (code) {
    const own = SESSION_MESSAGES[code]
    if (own) return own
  }
  return messageForCode(code, serverMessage)
}
