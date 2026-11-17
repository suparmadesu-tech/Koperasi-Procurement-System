import { describe, expect, it } from 'vitest';
import {
  effectivePrice,
  formatRupiah,
  isValidPrice,
  parseAmount,
  roundRupiah,
  subtotal,
  sumSubtotals,
} from './money';

describe('roundRupiah (half away from zero)', () => {
  it.each([
    ['2.5', '3'],
    ['0.5', '1'],
    ['1.4999', '1'],
    ['1666.5', '1667'],
    ['-2.5', '-3'],
    ['-0.5', '-1'],
    ['-1.4', '-1'],
    ['0', '0'],
  ])('%s menjadi %s', (input, expected) => {
    expect(roundRupiah(input).toString()).toBe(expected);
  });
});

describe('subtotal dan total (CK-06)', () => {
  it('harga 3.333 x 0,5 = 1.667 dan harga 1.000 x 2 = 2.000, total 3.667', () => {
    const a = subtotal('3333', '0.5');
    const b = subtotal('1000', '2');
    expect(a?.toString()).toBe('1667');
    expect(b?.toString()).toBe('2000');
    expect(sumSubtotals([a, b, null]).toString()).toBe('3667');
  });

  it('tidak terkena kesalahan floating point (1,005 x 100)', () => {
    expect(subtotal('100', '1.005')?.toString()).toBe('101');
    expect(subtotal(100, 1.005)?.toString()).toBe('101');
  });

  it('jumlah pecahan kecil dibulatkan per barang', () => {
    expect(subtotal(3, 0.1)?.toString()).toBe('0');
    expect(subtotal(10, 0.35)?.toString()).toBe('4');
    expect(subtotal('3333', '0.25')?.toString()).toBe('833');
  });

  it('harga 0 sah (bukan barang tanpa harga), harga atau jumlah kosong tidak dihitung', () => {
    expect(subtotal('0', '3')?.toString()).toBe('0');
    expect(subtotal(null, '3')).toBeNull();
    expect(subtotal('1000', null)).toBeNull();
    expect(subtotal(undefined, undefined)).toBeNull();
  });

  it('total tanpa subtotal bernilai 0', () => {
    expect(sumSubtotals([]).toString()).toBe('0');
    expect(sumSubtotals([null, null]).toString()).toBe('0');
  });
});

describe('effectivePrice (CK-03, CK-10)', () => {
  it('memakai price_actual bila terisi, termasuk 0', () => {
    expect(effectivePrice('11000', '10000')?.toString()).toBe('11000');
    expect(effectivePrice('0', '5000')?.toString()).toBe('0');
  });

  it('kembali ke price_snapshot bila price_actual kosong', () => {
    expect(effectivePrice(null, '10000')?.toString()).toBe('10000');
    expect(effectivePrice(undefined, 10000)?.toString()).toBe('10000');
  });

  it('keduanya kosong berarti tanpa harga efektif', () => {
    expect(effectivePrice(null, null)).toBeNull();
    expect(effectivePrice(undefined, undefined)).toBeNull();
  });
});

describe('isValidPrice (FR-038)', () => {
  it('menerima Rupiah bulat tidak negatif', () => {
    expect(isValidPrice('1000')).toBe(true);
    expect(isValidPrice(0)).toBe(true);
    expect(isValidPrice(1000)).toBe(true);
  });

  it('menolak pecahan, negatif, kosong, dan bukan angka', () => {
    expect(isValidPrice('1000.5')).toBe(false);
    expect(isValidPrice('-1')).toBe(false);
    expect(isValidPrice(null)).toBe(false);
    expect(isValidPrice('')).toBe(false);
    expect(isValidPrice('abc')).toBe(false);
    expect(isValidPrice(Number.NaN)).toBe(false);
  });
});

describe('parseAmount', () => {
  it('kosong menjadi null, tidak valid melempar RangeError', () => {
    expect(parseAmount('')).toBeNull();
    expect(parseAmount('  ')).toBeNull();
    expect(parseAmount(null)).toBeNull();
    expect(() => parseAmount('abc')).toThrow(RangeError);
    expect(() => parseAmount(Number.POSITIVE_INFINITY)).toThrow(RangeError);
  });
});

describe('formatRupiah', () => {
  it('memakai titik sebagai pemisah ribuan', () => {
    expect(formatRupiah('3667')).toBe('Rp 3.667');
    expect(formatRupiah(1234567)).toBe('Rp 1.234.567');
    expect(formatRupiah('999')).toBe('Rp 999');
  });

  it('nol, pembulatan ke nol, dan negatif', () => {
    expect(formatRupiah(0)).toBe('Rp 0');
    expect(formatRupiah('-0.4')).toBe('Rp 0');
    expect(formatRupiah('-1500')).toBe('-Rp 1.500');
    expect(formatRupiah('1666.5')).toBe('Rp 1.667');
  });
});
