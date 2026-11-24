import { formatRupiah } from '../../lib/money'
import { unpricedLabel } from '../daftar/listView'

export interface StartFacts {
  itemCount: number
  total: string
  unpricedCount: number
}

// Angka berasal dari data daftar di perangkat ini; server menghitung ulang dan membekukan saat sesi dimulai (FR-024).
export function startDialogMessage(facts: StartFacts, catalogPending: boolean, note: string): string {
  const parts: string[] = []
  if (facts.itemCount === 0) {
    parts.push('Daftar kebutuhan kosong, jadi sesi dimulai tanpa barang.')
  } else {
    parts.push(`${facts.itemCount} barang di daftar kebutuhan akan dipindahkan ke sesi.`)
    parts.push(`Perkiraan estimasi dari harga katalog saat ini: ${formatRupiah(facts.total)}.`)
    if (facts.unpricedCount > 0) parts.push(`${unpricedLabel(facts.unpricedCount)}.`)
    if (catalogPending) parts.push('Katalog belum termuat di perangkat ini, jadi angka ini mungkin belum lengkap.')
    parts.push('Angka ini dari data daftar di perangkat ini. Estimasi awal dibekukan oleh server saat sesi dimulai.')
  }
  if (note) parts.push(note)
  return parts.join(' ')
}

export function endDialogMessage(returnCount: number, note: string): string {
  const parts: string[] = []
  parts.push(
    returnCount > 0
      ? `${returnCount} barang memiliki sisa kebutuhan dan akan dikembalikan ke daftar kebutuhan.`
      : 'Tidak ada barang yang perlu dikembalikan ke daftar.',
  )
  parts.push('Barang yang sudah dibeli sesuai kebutuhan tidak dikembalikan.')
  parts.push('Total aktual dan riwayat dibekukan dari data di server. Hitungan barang di atas dari data di perangkat ini.')
  if (note) parts.push(note)
  return parts.join(' ')
}

export const CANCEL_DIALOG_MESSAGE =
  'Semua barang sesi dikembalikan ke daftar kebutuhan dengan jumlah kebutuhan terakhir. Barang yang ditambahkan langsung ke sesi dan sudah dihapus tidak dikembalikan. Sesi dibatalkan tidak masuk riwayat belanja dan hanya tercatat di log aktivitas. Pembatalan tidak dapat diurungkan.'
