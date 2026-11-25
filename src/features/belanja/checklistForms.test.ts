import { describe, expect, it } from 'vitest'
import {
  actualQuantityPrefill,
  planActualQuantity,
  planPriceActual,
  priceActualPrefill,
  priceOkText,
  quantityOkText,
  statusOkText,
} from './checklistForms'

const cart = { status: 'in_cart' as const, actual: '2', allowFraction: true }

describe('planActualQuantity (FR-032)', () => {
  it('to_buy ditolak di klien dengan alasan yang jelas, tanpa mengirim', () => {
    const p = planActualQuantity({ status: 'to_buy', actual: null, allowFraction: true }, '2')
    expect(p).toMatchObject({ kind: 'invalid' })
  })

  it('0 diterima, koma desimal, dan maksimal 3 desimal', () => {
    expect(planActualQuantity(cart, '0')).toEqual({ kind: 'send', value: '0' })
    expect(planActualQuantity(cart, '1,5')).toEqual({ kind: 'send', value: '1.5' })
    expect(planActualQuantity(cart, '0,0001')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity(cart, '')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity(cart, '-1')).toMatchObject({ kind: 'invalid' })
  })

  it('pecahan mengikuti allow_fraction_snapshot', () => {
    expect(planActualQuantity({ ...cart, allowFraction: false }, '0,5')).toMatchObject({ kind: 'invalid' })
    expect(planActualQuantity({ ...cart, allowFraction: false }, '3')).toEqual({ kind: 'send', value: '3' })
  })

  it('nilai yang sama tidak dikirim', () => {
    expect(planActualQuantity(cart, '2')).toEqual({ kind: 'noop' })
    expect(planActualQuantity(cart, '2,0')).toEqual({ kind: 'noop' })
  })
})

describe('planPriceActual (FR-053)', () => {
  const noActual = { price: '10000', priceIsActual: false }
  const withActual = { price: '11000', priceIsActual: true }

  it('kosong mengosongkan hanya bila harga aktual terisi', () => {
    expect(planPriceActual(withActual, '')).toEqual({ kind: 'send', value: null })
    expect(planPriceActual(noActual, '')).toEqual({ kind: 'noop' })
    expect(planPriceActual({ price: null, priceIsActual: false }, '  ')).toEqual({ kind: 'noop' })
  })

  it('0 sah dan dikirim sebagai harga, bukan dianggap kosong', () => {
    expect(planPriceActual(noActual, '0')).toEqual({ kind: 'send', value: '0' })
    expect(planPriceActual(withActual, 'Rp 0')).toEqual({ kind: 'send', value: '0' })
  })

  it('format Rupiah, pecahan, dan negatif', () => {
    expect(planPriceActual(noActual, 'Rp 12.500')).toEqual({ kind: 'send', value: '12500' })
    expect(planPriceActual(noActual, '12,5')).toMatchObject({ kind: 'invalid' })
    expect(planPriceActual(noActual, '-1')).toMatchObject({ kind: 'invalid' })
  })

  it('harga yang sama dengan harga aktual sekarang tidak dikirim; harga awal sesi bukan harga aktual', () => {
    expect(planPriceActual(withActual, '11.000')).toEqual({ kind: 'noop' })
    expect(planPriceActual(noActual, '10000')).toEqual({ kind: 'send', value: '10000' })
  })
})

describe('isi awal formulir', () => {
  it('jumlah aktual memakai koma; harga hanya bila harga aktual terisi', () => {
    expect(actualQuantityPrefill({ actual: '1.5' })).toBe('1,5')
    expect(actualQuantityPrefill({ actual: null })).toBe('')
    expect(priceActualPrefill({ price: '11000', priceIsActual: true })).toBe('11000')
    expect(priceActualPrefill({ price: '10000', priceIsActual: false })).toBe('')
    expect(priceActualPrefill({ price: null, priceIsActual: false })).toBe('')
  })
})

describe('teks setelah konfirmasi server', () => {
  it('menyebut dikonfirmasi server dan memakai format yang ada', () => {
    expect(statusOkText('Beras', 'in_cart')).toBe('Beras: status diubah menjadi Di keranjang (dikonfirmasi server).')
    expect(quantityOkText('Beras', '1.5', 'kg')).toBe('Jumlah aktual Beras menjadi 1,5 kg (dikonfirmasi server).')
    expect(quantityOkText('Beras', '2', '')).toBe('Jumlah aktual Beras menjadi 2 (dikonfirmasi server).')
    expect(priceOkText('Beras', '11000')).toBe('Harga aktual Beras menjadi Rp 11.000 (dikonfirmasi server).')
    expect(priceOkText('Beras', '0')).toBe('Harga aktual Beras menjadi Rp 0 (dikonfirmasi server).')
    expect(priceOkText('Beras', null)).toContain('dikosongkan')
  })
})
