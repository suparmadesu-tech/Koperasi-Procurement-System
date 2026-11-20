import { describe, expect, it } from 'vitest'
import { parseQuantityInput, validateCatalogAddForm, validateManualItemForm } from './validation'

const frac = { allowFraction: true }
const whole = { allowFraction: false }

describe('parseQuantityInput', () => {
  it('menerima koma dan titik sebagai desimal dan menormalkan nilai', () => {
    expect(parseQuantityInput('1,5', frac)).toEqual({ ok: true, value: '1.5' })
    expect(parseQuantityInput(' 2.0 ', frac)).toEqual({ ok: true, value: '2' })
    expect(parseQuantityInput('.5', frac)).toEqual({ ok: true, value: '0.5' })
    expect(parseQuantityInput('0,001', frac)).toEqual({ ok: true, value: '0.001' })
    expect(parseQuantityInput('999999999,999', frac).ok).toBe(true)
  })

  it('menolak kosong, nol, negatif, bukan angka, dan format ganda', () => {
    for (const bad of ['', '  ', '0', '0,0', '-1', 'abc', '1.2.3', '1,2,3', '1e3']) {
      expect(parseQuantityInput(bad, frac).ok).toBe(false)
    }
  })

  it('menolak lebih dari 3 desimal dan nilai 1 miliar atau lebih', () => {
    expect(parseQuantityInput('0,0001', frac).ok).toBe(false)
    expect(parseQuantityInput('1000000000', frac).ok).toBe(false)
  })

  it('pecahan mengikuti satuan', () => {
    expect(parseQuantityInput('0,5', whole).ok).toBe(false)
    expect(parseQuantityInput('2', whole)).toEqual({ ok: true, value: '2' })
    expect(parseQuantityInput('2,0', whole)).toEqual({ ok: true, value: '2' })
  })
})

describe('validateManualItemForm', () => {
  const base = { name: 'Plastik', unit: 'pak', quantityText: '1,5', note: '' }

  it('menerima pecahan untuk barang manual dan mengubah catatan kosong menjadi null', () => {
    const r = validateManualItemForm(base)
    expect(r).toEqual({ ok: true, value: { name: 'Plastik', unit: 'pak', quantity: '1.5', note: null } })
  })

  it('batas panjang tepat diterima dan lebih satu ditolak (BR-039)', () => {
    expect(validateManualItemForm({ ...base, name: 'a'.repeat(200) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
    expect(validateManualItemForm({ ...base, unit: 'a'.repeat(50) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, unit: 'a'.repeat(51) }).ok).toBe(false)
    expect(validateManualItemForm({ ...base, note: 'a'.repeat(1000) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, note: 'a'.repeat(1001) }).ok).toBe(false)
  })

  it('menghitung panjang per code point', () => {
    expect(validateManualItemForm({ ...base, name: '😀'.repeat(200) }).ok).toBe(true)
    expect(validateManualItemForm({ ...base, name: '😀'.repeat(201) }).ok).toBe(false)
  })

  it('mewajibkan nama, satuan, dan jumlah, serta melaporkan semua galat sekaligus', () => {
    const r = validateManualItemForm({ name: '  ', unit: '', quantityText: '', note: '' })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(['name', 'quantity', 'unit'])
  })
})

describe('validateCatalogAddForm', () => {
  it('mewajibkan barang dan memakai aturan pecahan satuan', () => {
    expect(validateCatalogAddForm({ productId: '', quantityText: '1', allowFraction: true }).ok).toBe(false)
    expect(validateCatalogAddForm({ productId: 'p1', quantityText: '0,5', allowFraction: false }).ok).toBe(false)
    expect(validateCatalogAddForm({ productId: 'p1', quantityText: '0,5', allowFraction: true })).toEqual({
      ok: true,
      value: { productId: 'p1', quantity: '0.5' },
    })
  })
})
