import { D } from '../../lib/money'

// Batas kolom kps_rupiah di database.
export const MAX_RUPIAH = '99999999999999'

export type PriceParse = { ok: true; value: string | null } | { ok: false; message: string }

const PLAIN = /^\d+$/
const GROUPED = /^\d{1,3}(\.\d{3})+$/

// Menerima "12500", "12.500", "Rp 12.500", "12.500,00". Kosong berarti harga belum ada.
export function parsePriceInput(raw: string): PriceParse {
  let text = raw.trim().replace(/^rp\.?\s*/i, '').replace(/\s+/g, '')
  if (text === '') return { ok: true, value: null }
  if (text.startsWith('-')) return { ok: false, message: 'Harga tidak boleh negatif.' }

  const comma = text.indexOf(',')
  if (comma !== -1) {
    if (!/^0*$/.test(text.slice(comma + 1))) {
      return { ok: false, message: 'Harga harus Rupiah bulat, tanpa pecahan.' }
    }
    text = text.slice(0, comma)
  }
  if (!PLAIN.test(text) && !GROUPED.test(text)) {
    return { ok: false, message: 'Harga hanya boleh berisi angka, contoh 12500 atau 12.500.' }
  }
  const value = new D(text.replace(/\./g, ''))
  if (!value.lte(MAX_RUPIAH)) return { ok: false, message: 'Harga terlalu besar.' }
  return { ok: true, value: value.toFixed(0) }
}
