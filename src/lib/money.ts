import Decimal from 'decimal.js';

// Konfigurasi terpisah dari Decimal global. ROUND_HALF_UP pada decimal.js berarti
// nilai tepat di tengah dibulatkan menjauhi nol (FR-036).
export const D = Decimal.clone({
  precision: 40,
  rounding: Decimal.ROUND_HALF_UP,
  toExpNeg: -9e15,
  toExpPos: 9e15,
});

export type Amount = string | number | Decimal | null | undefined;

// null atau teks kosong berarti "tidak ada nilai". Nilai tidak valid melempar RangeError.
export function parseAmount(v: Amount): Decimal | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'string' && v.trim() === '') return null;
  let d: Decimal;
  try {
    d = new D(typeof v === 'string' ? v.trim() : v);
  } catch {
    throw new RangeError('Angka tidak valid');
  }
  if (!d.isFinite()) throw new RangeError('Angka tidak valid');
  return d;
}

// Rupiah penuh, half away from zero.
export function roundRupiah(v: string | number | Decimal): Decimal {
  return new D(v).toDecimalPlaces(0, D.ROUND_HALF_UP);
}

// Harga: Rupiah bulat dan tidak negatif (FR-038). 0 sah.
export function isValidPrice(v: Amount): boolean {
  try {
    const d = parseAmount(v);
    return d !== null && d.gte(0) && d.isInteger();
  } catch {
    return false;
  }
}

// FR-053: price_actual bila terisi (0 sah), jika tidak price_snapshot.
export function effectivePrice(priceActual: Amount, priceSnapshot: Amount): Decimal | null {
  return parseAmount(priceActual) ?? parseAmount(priceSnapshot);
}

// FR-036: pembulatan(harga x jumlah). null bila harga atau jumlah tidak ada.
export function subtotal(price: Amount, quantity: Amount): Decimal | null {
  const p = parseAmount(price);
  const q = parseAmount(quantity);
  if (p === null || q === null) return null;
  return roundRupiah(p.mul(q));
}

// Total = jumlah subtotal yang sudah dibulatkan, tanpa pembulatan ulang.
export function sumSubtotals(list: (Decimal | null)[]): Decimal {
  let total = new D(0);
  for (const s of list) {
    if (s !== null) total = total.plus(s);
  }
  return total;
}

export function formatRupiah(v: string | number | Decimal): string {
  const r = roundRupiah(v);
  if (r.isZero()) return 'Rp 0';
  const digits = r.abs().toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${r.isNegative() ? '-' : ''}Rp ${digits}`;
}
