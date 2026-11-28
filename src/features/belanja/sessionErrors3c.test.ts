import { describe, expect, it } from 'vitest'
import { sessionMessageForCode } from './sessionErrors'

describe('pesan penolakan saat menambah barang ke sesi', () => {
  it('semua kode FR-052 punya pesan Indonesia sendiri, bukan pesan server', () => {
    const expected: Record<string, string> = {
      KPS_SESSION_NOT_ACTIVE: 'selesai atau dibatalkan',
      KPS_PRODUCT_ARCHIVED: 'diarsipkan',
      KPS_FRACTION_NOT_ALLOWED: 'berpecahan',
      KPS_INVALID_QUANTITY: 'lebih dari 0',
      KPS_TEXT_TOO_LONG: 'maksimal 200',
      KPS_CONFLICT: 'sudah ada di sesi',
      KPS_PHOTO_NOT_FOUND: 'belum ditambahkan',
      KPS_INVALID_PHOTO_PATH: 'tidak valid',
    }
    for (const [code, part] of Object.entries(expected)) {
      const m = sessionMessageForCode(code, 'PESAN-SERVER-ASING')
      expect(m).toContain(part)
      expect(m).not.toContain('PESAN-SERVER-ASING')
    }
  })

  it('pesan lama tidak berubah dan kode tak dikenal tetap jatuh ke pesan server', () => {
    expect(sessionMessageForCode('KPS_ITEM_DELETED')).toContain('dihapus dari sesi')
    expect(sessionMessageForCode('KPS_BARU', 'dari server')).toBe('dari server')
  })

  it('kegagalan foto tidak menyiratkan barang tersimpan', () => {
    expect(sessionMessageForCode('KPS_PHOTO_NOT_FOUND')).toContain('belum ditambahkan')
    expect(sessionMessageForCode('KPS_INVALID_PHOTO_PATH')).toContain('belum ditambahkan')
  })
})
