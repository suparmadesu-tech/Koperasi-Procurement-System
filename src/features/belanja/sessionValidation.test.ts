import { describe, expect, it } from 'vitest'
import {
  parseActualQuantityInput,
  parseNeededQuantityInput,
  parsePriceActualInput,
  validateSessionCatalogForm,
  validateSessionManualForm,
} from './sessionValidation'

describe('parseActualQuantityInput', () => {
  it('menerima 0 dan pecahan sesuai snapshot', () => {
    expect(parseActualQuantityInput('0', { allowFraction: false })).toEqual({ ok: true, value: '0' })
    expect(parseActualQuantityInput('0,0', { allowFraction: true })).toEqual({ ok: true, value: '0' })
    expect(parseActualQuantityInput('0,25', { allowFraction: true })).toEqual({ ok: true, value: '0.25' })
    expect(parseActualQuantityInput('0,25', { allowFraction: false }).ok).toBe(false)
  })

  it('menolak kosong, negatif, bukan angka, dan lebih dari 3 desimal', () => {
    for (const bad of ['', '-1', 'abc', '0,0001', '1000000000']) {
      expect(parseActualQuantityInput(bad, { allowFraction: true }).ok).toBe(false)
    }
  })
})

describe('jumlah kebutuhan langsung', () => {
  it('harus lebih dari 0', () => {
    expect(parseNeededQuantityInput('0', { allowFraction: true }).ok).toBe(false)
    expect(parseNeededQuantityInput('3', { allowFraction: false })).toEqual({ ok: true, value: '3' })
  })
})

describe('parsePriceActualInput', () => {
  it('kosong mengosongkan, 0 sah, pecahan dan negatif ditolak', () => {
    expect(parsePriceActualInput('')).toEqual({ ok: true, value: null })
    expect(parsePriceActualInput('0')).toEqual({ ok: true, value: '0' })
    expect(parsePriceActualInput('Rp 12.500')).toEqual({ ok: true, value: '12500' })
    expect(parsePriceActualInput('12,5').ok).toBe(false)
    expect(parsePriceActualInput('-1').ok).toBe(false)
  })
})

describe('validateSessionCatalogForm', () => {
  const base = { productId: 'p1', quantityText: '2', note: '', allowFraction: false }

  it('batas catatan 1000 karakter (BR-039) dan catatan kosong menjadi null', () => {
    expect(validateSessionCatalogForm({ ...base, note: 'a'.repeat(1000) }).ok).toBe(true)
    expect(validateSessionCatalogForm({ ...base, note: 'a'.repeat(1001) }).ok).toBe(false)
    expect(validateSessionCatalogForm(base)).toEqual({ ok: true, value: { productId: 'p1', quantity: '2', note: null } })
  })

  it('mewajibkan barang dan menerapkan aturan pecahan', () => {
    expect(validateSessionCatalogForm({ ...base, productId: '' }).ok).toBe(false)
    expect(validateSessionCatalogForm({ ...base, quantityText: '0,5' }).ok).toBe(false)
    expect(validateSessionCatalogForm({ ...base, quantityText: '0,5', allowFraction: true }).ok).toBe(true)
  })
})

describe('validateSessionManualForm', () => {
  it('memakai batas yang sama dengan daftar', () => {
    const base = { name: 'Plastik', unit: 'pak', quantityText: '1,5', note: '' }
    expect(validateSessionManualForm(base).ok).toBe(true)
    expect(validateSessionManualForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
    expect(validateSessionManualForm({ ...base, unit: 'a'.repeat(51) }).ok).toBe(false)
  })
})
