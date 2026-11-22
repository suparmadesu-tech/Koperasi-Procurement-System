import { describe, expect, it } from 'vitest'
import {
  addCatalogToSessionPayload,
  addManualToSessionPayload,
  cancelSessionPayload,
  deleteItemPayload,
  endSessionPayload,
  setPriceActualPayload,
  setQuantityActualPayload,
  setQuantityNeededPayload,
  setSessionPhotoPayload,
  setStatusPayload,
  startSessionPayload,
} from './sessionPayloads'

describe('payload sesi', () => {
  it('mulai, akhiri, batalkan', () => {
    expect(startSessionPayload()).toEqual({})
    expect(endSessionPayload('s1')).toEqual({ session_id: 's1' })
    expect(cancelSessionPayload('s1')).toEqual({ session_id: 's1' })
  })

  it('tambah katalog ke sesi: note hanya bila ada, kuantitas angka', () => {
    expect(addCatalogToSessionPayload('s1', 'p1', '1.5', null)).toEqual({ session_id: 's1', product_id: 'p1', quantity: 1.5 })
    expect(addCatalogToSessionPayload('s1', 'p1', '2', 'merah')).toEqual({
      session_id: 's1', product_id: 'p1', quantity: 2, note: 'merah',
    })
  })

  it('tambah barang manual ke sesi menghilangkan kunci opsional yang kosong', () => {
    const base = { sessionId: 's1', id: 'u1', name: 'Plastik', unit: 'pak', quantity: '1.5', note: null, photoPath: null }
    expect(addManualToSessionPayload(base)).toEqual({ session_id: 's1', id: 'u1', name: 'Plastik', unit: 'pak', quantity: 1.5 })
    expect(addManualToSessionPayload({ ...base, note: 'tebal', photoPath: 'w/u.jpg' })).toMatchObject({
      note: 'tebal',
      photo_path: 'w/u.jpg',
    })
  })

  it('operasi barang sesi', () => {
    expect(setStatusPayload('i1', 'in_cart')).toEqual({ item_id: 'i1', status: 'in_cart' })
    expect(setQuantityActualPayload('i1', '0.25')).toEqual({ item_id: 'i1', quantity: 0.25 })
    expect(setQuantityNeededPayload('i1', '3')).toEqual({ item_id: 'i1', quantity: 3 })
    expect(deleteItemPayload('i1')).toEqual({ item_id: 'i1' })
    expect(setSessionPhotoPayload('i1', 'w/u.webp')).toEqual({ item_id: 'i1', photo_path: 'w/u.webp' })
  })

  it('harga aktual: null mengosongkan, 0 tetap 0', () => {
    expect(setPriceActualPayload('i1', null)).toEqual({ item_id: 'i1', price: null })
    expect(setPriceActualPayload('i1', '0')).toEqual({ item_id: 'i1', price: 0 })
    expect(setPriceActualPayload('i1', '11000')).toEqual({ item_id: 'i1', price: 11000 })
  })
})
