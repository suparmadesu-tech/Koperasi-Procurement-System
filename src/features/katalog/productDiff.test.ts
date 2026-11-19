import { describe, expect, it } from 'vitest'
import { diffProduct } from './productDiff'
import type { ProductRow } from './types'

const current: ProductRow = {
  id: 'p',
  workspace_id: 'w',
  category_id: 'c1',
  unit_id: 'u1',
  name: 'Gula',
  photo_path: null,
  price: '12500',
  is_archived: false,
  updated_at: '2026-11-18T00:00:00Z',
}
const same = { name: 'Gula', categoryId: 'c1', unitId: 'u1', price: '12500' }

describe('diffProduct', () => {
  it('tidak ada perubahan menghasilkan objek kosong', () => {
    expect(diffProduct(current, same, false)).toEqual({})
  })
  it('hanya memuat kolom yang berubah', () => {
    expect(diffProduct(current, { ...same, name: 'Gula Pasir', unitId: 'u2' }, false)).toEqual({
      name: 'Gula Pasir',
      unitId: 'u2',
    })
  })
  it('mengosongkan harga mengirim null, harga 0 dianggap perubahan', () => {
    expect(diffProduct(current, { ...same, price: null }, false)).toEqual({ price: null })
    expect(diffProduct(current, { ...same, price: '0' }, false)).toEqual({ price: '0' })
  })
  it('harga sama dengan sisa nol desimal dari server tidak dianggap berubah', () => {
    expect(diffProduct({ ...current, price: '12500.00' }, same, false)).toEqual({})
  })
  it('mengarsipkan dan mengaktifkan kembali', () => {
    expect(diffProduct(current, same, true)).toEqual({ isArchived: true })
    expect(diffProduct({ ...current, is_archived: true }, same, false)).toEqual({ isArchived: false })
  })
})
