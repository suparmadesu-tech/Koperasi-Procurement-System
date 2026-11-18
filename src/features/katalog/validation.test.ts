import { describe, expect, it } from 'vitest'
import { parsePriceInput } from './moneyAdapter'
import { validateCategoryForm, validateProductForm, validateUnitForm } from './validation'

describe('parsePriceInput', () => {
  it.each([
    ['', null],
    ['   ', null],
    ['0', '0'],
    ['12500', '12500'],
    ['12.500', '12500'],
    ['Rp 12.500', '12500'],
    ['1.000.000', '1000000'],
    ['10,00', '10'],
    ['007', '7'],
    ['99999999999999', '99999999999999'],
  ])('menerima %j sebagai %j', (input, expected) => {
    expect(parsePriceInput(input)).toEqual({ ok: true, value: expected })
  })

  it.each(['-1', '10,5', '10.5', '1.00', 'abc', '12 500x', '100000000000000', ',5'])(
    'menolak %j',
    (input) => {
      expect(parsePriceInput(input).ok).toBe(false)
    },
  )
})

describe('validateCategoryForm', () => {
  it('memangkas spasi dan menerima tepat 200 karakter', () => {
    const r = validateCategoryForm({ name: `  ${'a'.repeat(200)}  ` })
    expect(r).toEqual({ ok: true, value: { name: 'a'.repeat(200) } })
  })
  it('menolak kosong dan 201 karakter', () => {
    expect(validateCategoryForm({ name: '   ' }).ok).toBe(false)
    expect(validateCategoryForm({ name: 'a'.repeat(201) }).ok).toBe(false)
  })
  it('menghitung per code point, bukan per unit UTF-16', () => {
    expect(validateCategoryForm({ name: '😀'.repeat(200) }).ok).toBe(true)
    expect(validateCategoryForm({ name: '😀'.repeat(201) }).ok).toBe(false)
  })
})

describe('validateUnitForm', () => {
  it('batas 50 karakter dan membawa allow_fraction', () => {
    expect(validateUnitForm({ name: 'k'.repeat(50), allowFraction: true })).toEqual({
      ok: true,
      value: { name: 'k'.repeat(50), allow_fraction: true },
    })
    expect(validateUnitForm({ name: 'k'.repeat(51), allowFraction: false }).ok).toBe(false)
  })
})

describe('validateProductForm', () => {
  const base = { name: 'Beras 5 kg', categoryId: 'c1', unitId: 'u1', priceText: '65.000' }
  it('menerima isian lengkap dan harga kosong', () => {
    expect(validateProductForm(base)).toEqual({
      ok: true,
      value: { name: 'Beras 5 kg', categoryId: 'c1', unitId: 'u1', price: '65000' },
    })
    expect(validateProductForm({ ...base, priceText: '' })).toMatchObject({ ok: true, value: { price: null } })
  })
  it('mengumpulkan semua galat sekaligus', () => {
    const r = validateProductForm({ name: '', categoryId: '', unitId: '', priceText: '-5' })
    expect(r.ok).toBe(false)
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(['categoryId', 'name', 'price', 'unitId'])
  })
  it('menolak nama 201 karakter', () => {
    expect(validateProductForm({ ...base, name: 'a'.repeat(201) }).ok).toBe(false)
  })
})
