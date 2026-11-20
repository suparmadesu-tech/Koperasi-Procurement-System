import { describe, expect, it } from 'vitest'
import {
  addCatalogPayload,
  addManualPayload,
  deletePayload,
  setPhotoPayload,
  setQuantityPayload,
} from './payloads'
import { toListItemRow } from './rows'

describe('toListItemRow', () => {
  it('menyimpan kuantitas sebagai string desimal', () => {
    const base = {
      id: 'i', workspace_id: 'w', shopping_list_id: 'l', product_id: null, manual_name: 'A',
      manual_unit: 'kg', photo_path: null, note: null, created_at: '', updated_at: '',
    }
    expect(toListItemRow({ ...base, quantity_needed: 0.5 }).quantity_needed).toBe('0.5')
    expect(toListItemRow({ ...base, quantity_needed: '2.000' }).quantity_needed).toBe('2')
  })
})

describe('payload operasi daftar', () => {
  it('memakai kunci sesuai kontrak kps_apply_op', () => {
    expect(addCatalogPayload('p1', '1.5')).toEqual({ product_id: 'p1', quantity: 1.5 })
    expect(setQuantityPayload('i1', '3')).toEqual({ item_id: 'i1', quantity: 3 })
    expect(deletePayload('i1')).toEqual({ item_id: 'i1' })
    expect(setPhotoPayload('i1', 'w/u.webp')).toEqual({ item_id: 'i1', photo_path: 'w/u.webp' })
  })

  it('menghilangkan kunci opsional yang kosong pada barang manual', () => {
    const base = { id: 'u1', name: 'Plastik', unit: 'pak', quantity: '2', note: null, photoPath: null }
    expect(addManualPayload(base)).toEqual({ id: 'u1', name: 'Plastik', unit: 'pak', quantity: 2 })
    expect(addManualPayload({ ...base, note: 'tebal', photoPath: 'w/u.jpg' })).toEqual({
      id: 'u1', name: 'Plastik', unit: 'pak', quantity: 2, note: 'tebal', photo_path: 'w/u.jpg',
    })
  })
})
