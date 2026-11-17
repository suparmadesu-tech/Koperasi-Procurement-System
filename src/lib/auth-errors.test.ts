import { describe, expect, it } from 'vitest';
import { mapAuthError } from './auth-errors';

describe('mapAuthError', () => {
  it('jaringan terputus', () => {
    expect(mapAuthError({ name: 'AuthRetryableFetchError', status: 0 })).toContain('koneksi');
    expect(mapAuthError({ message: 'Failed to fetch' })).toContain('koneksi');
  });

  it('kredensial salah, lewat kode maupun pesan', () => {
    expect(mapAuthError({ code: 'invalid_credentials', status: 400 })).toBe(
      'Email atau kata sandi salah.',
    );
    expect(mapAuthError({ message: 'Invalid login credentials' })).toBe(
      'Email atau kata sandi salah.',
    );
  });

  it('batas permintaan', () => {
    expect(mapAuthError({ status: 429 })).toContain('Terlalu banyak');
  });

  it('email belum dikonfirmasi', () => {
    expect(mapAuthError({ code: 'email_not_confirmed' })).toContain('belum dikonfirmasi');
  });

  it('galat tak dikenal dan nilai kosong memakai pesan umum', () => {
    expect(mapAuthError({ message: 'aneh' })).toContain('Gagal masuk');
    expect(mapAuthError(null)).toContain('Gagal masuk');
  });
});
