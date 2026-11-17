import { describe, expect, it } from 'vitest';
import { MAX_SEND_ATTEMPTS, RETRY_DELAYS_MS, planRetry } from './retry-schedule';

describe('planRetry (SYNC-005, OF-12)', () => {
  it('jadwal jeda 5 detik, 30 detik, 2 menit, 10 menit', () => {
    expect(RETRY_DELAYS_MS).toEqual([5_000, 30_000, 120_000, 600_000]);
    expect(MAX_SEND_ATTEMPTS).toBe(5);
  });

  it('kegagalan ke-1 sampai ke-4 dijadwalkan ulang', () => {
    expect(planRetry(0, true)).toEqual({ kind: 'retry_after', attempts: 1, delayMs: 5_000 });
    expect(planRetry(1, true)).toEqual({ kind: 'retry_after', attempts: 2, delayMs: 30_000 });
    expect(planRetry(2, true)).toEqual({ kind: 'retry_after', attempts: 3, delayMs: 120_000 });
    expect(planRetry(3, true)).toEqual({ kind: 'retry_after', attempts: 4, delayMs: 600_000 });
  });

  it('kegagalan ke-5 menghabiskan batas (awal dan 4 percobaan ulang)', () => {
    expect(planRetry(4, true)).toEqual({ kind: 'exhausted', attempts: 5 });
    expect(planRetry(7, true)).toEqual({ kind: 'exhausted', attempts: 8 });
  });

  it('saat offline percobaan tidak dihitung dan menunggu online', () => {
    expect(planRetry(0, false)).toEqual({ kind: 'wait_online', attempts: 0 });
    expect(planRetry(3, false)).toEqual({ kind: 'wait_online', attempts: 3 });
  });

  it('nilai tidak sah dianggap 0', () => {
    expect(planRetry(-2, true)).toEqual({ kind: 'retry_after', attempts: 1, delayMs: 5_000 });
  });
});
