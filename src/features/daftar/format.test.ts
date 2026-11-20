import { describe, expect, it } from 'vitest'
import { formatQuantity, formatTimeJakarta } from './format'

describe('formatQuantity', () => {
  it('memakai koma desimal dan titik ribuan', () => {
    expect(formatQuantity('1.5')).toBe('1,5')
    expect(formatQuantity('0.001')).toBe('0,001')
    expect(formatQuantity('2')).toBe('2')
    expect(formatQuantity('1000')).toBe('1.000')
    expect(formatQuantity('1234567.25')).toBe('1.234.567,25')
  })
})

describe('formatTimeJakarta', () => {
  it('menampilkan jam Asia/Jakarta', () => {
    expect(formatTimeJakarta('2026-11-20T07:32:00Z')).toMatch(/14[.:]32/)
  })
})
