import { describe, expect, it } from 'vitest'
import { sessionMessageForCode } from './sessionErrors'

describe('sessionMessageForCode', () => {
  it('memberi pesan Indonesia untuk penolakan sesi', () => {
    expect(sessionMessageForCode('KPS_SESSION_NOT_ACTIVE')).toContain('selesai atau dibatalkan')
    expect(sessionMessageForCode('KPS_SESSION_ALREADY_ACTIVE')).toContain('sesi belanja yang aktif')
    expect(sessionMessageForCode('KPS_ITEM_DELETED')).toContain('dihapus dari sesi')
    expect(sessionMessageForCode('KPS_INVALID_PRICE')).toContain('Rupiah bulat')
    expect(sessionMessageForCode('KPS_QUANTITY_ACTUAL_STATE')).toContain('keranjang')
  })

  it('kode lain jatuh ke pesan daftar, lalu ke pesan server, lalu ke pesan umum', () => {
    expect(sessionMessageForCode('KPS_FRACTION_NOT_ALLOWED')).toContain('berpecahan')
    expect(sessionMessageForCode('KPS_BARU', 'dari server')).toBe('dari server')
    expect(sessionMessageForCode(null)).toBe('Perubahan ditolak server.')
  })
})
