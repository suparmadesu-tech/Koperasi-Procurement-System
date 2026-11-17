// SYNC-005 dan T-16: 5 kali pengiriman (awal dan 4 percobaan ulang), jeda 5 detik,
// 30 detik, 2 menit, 10 menit. Percobaan hanya dihitung saat perangkat online.
export const MAX_SEND_ATTEMPTS = 5;
export const RETRY_DELAYS_MS: readonly number[] = [5_000, 30_000, 120_000, 600_000];

export type RetryPlan =
  | { kind: 'wait_online'; attempts: number }
  | { kind: 'retry_after'; attempts: number; delayMs: number }
  | { kind: 'exhausted'; attempts: number };

// attemptsBefore: pengiriman yang sudah dihitung sebelum pengiriman yang baru gagal.
export function planRetry(attemptsBefore: number, online: boolean): RetryPlan {
  const before = Math.max(0, Math.floor(attemptsBefore));
  if (!online) return { kind: 'wait_online', attempts: before };
  const attempts = before + 1;
  if (attempts >= MAX_SEND_ATTEMPTS) return { kind: 'exhausted', attempts };
  return { kind: 'retry_after', attempts, delayMs: RETRY_DELAYS_MS[attempts - 1] };
}
