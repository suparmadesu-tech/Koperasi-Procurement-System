import { describe, expect, it } from 'vitest'
import { productPatchToColumns, toProductRow } from './rows'

const server = {
  id: 'p',
  workspace_id: 'w',
  category_id: 'c',
  unit_id: 'u',
  name: 'Gula',
  photo_path: null,
  is_archived: false,
  updated_at: '2026-11-18T00:00:00Z',
}

describe('toProductRow', () => {
  it('mengubah harga angka menjadi string dan mempertahankan null', () => {
    expect(toProductRow({ ...server, price: 12500 }).price).toBe('12500')
    expect(toProductRow({ ...server, price: 0 }).price).toBe('0')
    expect(toProductRow({ ...server, price: null }).price).toBeNull()
  })
})

describe('productPatchToColumns', () => {
  it('hanya memuat kolom yang diubah dan memetakan nama kolom', () => {
    expect(productPatchToColumns({ categoryId: 'c2', isArchived: true })).toEqual({
      category_id: 'c2',
      is_archived: true,
    })
  })
  it('mengosongkan harga mengirim null dan harga 0 tetap 0', () => {
    expect(productPatchToColumns({ price: null })).toEqual({ price: null })
    expect(productPatchToColumns({ price: '0' })).toEqual({ price: 0 })
  })
  it('patch kosong menghasilkan objek kosong', () => {
    expect(productPatchToColumns({})).toEqual({})
  })
})
