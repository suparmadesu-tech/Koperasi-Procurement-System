import { describe, expect, it } from 'vitest';
import {
  classifyOutcome,
  failureKindFor,
  normalizeSendError,
  type SendError,
  type SendResult,
} from './sync-errors';

const fresh = { sessionRefreshed: false };
const refreshed = { sessionRefreshed: true };
const err = (error: SendError): SendResult => ({ kind: 'error', error });

describe('SYNC-020 no. 1: diterima', () => {
  it('diterima dan replayed berhasil', () => {
    expect(classifyOutcome({ kind: 'response', status: 'diterima' }, fresh)).toEqual({
      type: 'success',
    });
  });
});

describe('SYNC-020 no. 2: ditolak dengan kode apa pun', () => {
  it.each(['KPS_ITEM_MOVED', 'KPS_SESSION_NOT_ACTIVE', 'KPS_DEPENDENCY_REJECTED', null])(
    'kode %s langsung gagal tanpa percobaan ulang',
    (code) => {
      expect(classifyOutcome({ kind: 'response', status: 'ditolak', code }, fresh)).toEqual({
        type: 'fail_rejected',
        code,
      });
    },
  );
});

describe('SYNC-020 no. 3: galat otorisasi', () => {
  it.each([
    { kpsCode: 'KPS_FORBIDDEN' },
    { sqlState: '42501' },
    { httpStatus: 403 },
  ])('%o: segarkan sesi sekali, lalu kirim ulang', (error) => {
    expect(classifyOutcome(err(error), fresh)).toEqual({
      type: 'refresh_and_resend',
      reason: 'forbidden',
    });
  });

  it('masih ditolak setelah sesi disegarkan menjadi gagal', () => {
    expect(classifyOutcome(err({ kpsCode: 'KPS_FORBIDDEN' }), refreshed)).toEqual({
      type: 'fail_forbidden',
    });
    expect(classifyOutcome(err({ sqlState: '42501' }), refreshed)).toEqual({
      type: 'fail_forbidden',
    });
  });
});

describe('SYNC-020 no. 4: HTTP 401', () => {
  it('menyegarkan token lalu mengirim ulang tanpa menghabiskan percobaan', () => {
    expect(classifyOutcome(err({ httpStatus: 401 }), fresh)).toEqual({
      type: 'refresh_and_resend',
      reason: 'token_expired',
    });
  });

  it('tetap 401 setelah refresh berarti login ulang', () => {
    expect(classifyOutcome(err({ httpStatus: 401 }), refreshed)).toEqual({ type: 'needs_login' });
  });
});

describe('SYNC-020 no. 5: dapat diulang dan dihitung', () => {
  it.each([
    ['jaringan terputus', { network: true }],
    ['502', { httpStatus: 502 }],
    ['503', { httpStatus: 503 }],
    ['504', { httpStatus: 504 }],
    ['40001', { sqlState: '40001' }],
    ['40P01', { sqlState: '40P01' }],
    ['petunjuk RETRYABLE', { hint: 'RETRYABLE', sqlState: 'P0001' }],
    ['KPS_DEPENDENCY_MISSING', { kpsCode: 'KPS_DEPENDENCY_MISSING', hint: 'RETRYABLE' }],
    ['KPS_INTERNAL', { kpsCode: 'KPS_INTERNAL' }],
    ['galat tidak dikenali', { httpStatus: 500, message: 'aneh' }],
    ['kosong', {}],
  ] as [string, SendError][])('%s', (_, error) => {
    expect(classifyOutcome(err(error), fresh)).toEqual({ type: 'retry' });
  });

  it('jawaban dengan status tak dikenal juga dianggap tidak dikenali', () => {
    expect(classifyOutcome({ kind: 'response', status: 'entah' }, fresh)).toEqual({
      type: 'retry',
    });
  });
});

describe('SYNC-020 no. 6: langsung gagal', () => {
  it.each(['KPS_INVALID_INPUT', 'KPS_UNKNOWN_OP', 'KPS_OP_ID_CONFLICT'])('%s', (kpsCode) => {
    expect(classifyOutcome(err({ kpsCode }), fresh)).toEqual({ type: 'fail_invalid', code: kpsCode });
  });
});

describe('failureKindFor', () => {
  it('memetakan aksi gagal ke penyebabnya', () => {
    expect(failureKindFor({ type: 'fail_rejected', code: null })).toBe('rejected');
    expect(failureKindFor({ type: 'fail_invalid', code: 'KPS_INVALID_INPUT' })).toBe('invalid');
    expect(failureKindFor({ type: 'fail_forbidden' })).toBe('forbidden');
    expect(failureKindFor({ type: 'retry' })).toBeNull();
    expect(failureKindFor({ type: 'success' })).toBeNull();
  });
});

describe('normalizeSendError', () => {
  it('TypeError dan pesan jaringan menjadi network', () => {
    expect(normalizeSendError(new TypeError('Failed to fetch')).network).toBe(true);
    expect(normalizeSendError({ message: 'TypeError: Failed to fetch' }).network).toBe(true);
    expect(normalizeSendError({ name: 'AbortError', message: 'x' }).network).toBe(true);
  });

  it('memisahkan kode KPS, SQLSTATE, hint, dan status HTTP', () => {
    expect(normalizeSendError({ code: 'KPS_INTERNAL', message: 'x' }).kpsCode).toBe('KPS_INTERNAL');
    expect(normalizeSendError({ code: '40P01', message: 'deadlock' }).sqlState).toBe('40P01');
    const e = normalizeSendError(
      { code: 'P0001', message: 'KPS_DEPENDENCY_MISSING: belum diproses', hint: 'RETRYABLE' },
      400,
    );
    expect(e).toMatchObject({
      kpsCode: 'KPS_DEPENDENCY_MISSING',
      sqlState: 'P0001',
      hint: 'RETRYABLE',
      httpStatus: 400,
    });
  });

  it('kode PostgREST dan nilai bukan objek tidak dianggap SQLSTATE', () => {
    expect(normalizeSendError({ code: 'PGRST301', status: 401 })).toEqual({ httpStatus: 401 });
    expect(normalizeSendError(null)).toEqual({});
    expect(normalizeSendError('teks')).toEqual({});
  });
});
