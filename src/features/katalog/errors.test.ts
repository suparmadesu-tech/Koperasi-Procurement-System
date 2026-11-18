import { describe, expect, it } from 'vitest'
import { mapWriteError } from './errors'

describe('mapWriteError', () => {
  it.each([
    [{ message: 'Failed to fetch' }, 'OFFLINE'],
    [{ code: 'PGRST301', message: 'JWT expired' }, 'AUTH_EXPIRED'],
    [{ code: '42501', message: 'new row violates row-level security policy for table "products"' }, 'KPS_FORBIDDEN'],
    [{ code: '23503', message: 'violates foreign key constraint' }, 'KPS_REFERENCE_INVALID'],
    [{ code: '23505', message: 'duplicate key value violates unique constraint "categories_name_active_uq"' }, 'KPS_CONFLICT'],
    [{ code: '23514', message: 'value for domain kps_rupiah violates check constraint "kps_rupiah_check"' }, 'KPS_INVALID_PRICE'],
    [{ code: '23514', message: 'violates check constraint "products_name_len_chk"' }, 'KPS_TEXT_TOO_LONG'],
    [{ code: '23514', message: 'violates check constraint "products_photo_path_fmt_chk"' }, 'KPS_INVALID_PHOTO_PATH'],
    [{ code: '23514', message: 'violates check constraint "lainnya"' }, 'KPS_CHECK_VIOLATION'],
    [{ code: 'P0001', message: 'KPS_REF_ARCHIVED: kategori diarsipkan' }, 'KPS_REF_ARCHIVED'],
    [{ code: '22P02', message: 'invalid input syntax' }, 'KPS_INVALID_INPUT'],
    [{ code: 'XX000', message: 'boom' }, 'UNKNOWN'],
    [null, 'UNKNOWN'],
  ])('memetakan %j ke %s', (raw, code) => {
    expect(mapWriteError(raw).code).toBe(code)
  })

  it('membedakan pesan nama kategori dan nama satuan yang bentrok', () => {
    const k = mapWriteError({ code: '23505', message: 'constraint "categories_name_active_uq"' })
    const u = mapWriteError({ code: '23505', message: 'constraint "units_name_active_uq"' })
    expect(k.message).toContain('kategori')
    expect(u.message).toContain('satuan')
  })

  it('tidak memakai karakter em dash pada pesan', () => {
    expect(mapWriteError({ code: '42501' }).message).not.toContain('\u2014')
  })
})
