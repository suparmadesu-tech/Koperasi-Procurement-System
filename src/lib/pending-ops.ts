import { getDb } from './db';
import { UNSYNCED_STATUSES } from './queue-types';

// Jumlah operasi yang belum tersimpan di server: menunggu, sedang disinkronkan, gagal.
export async function countPendingOps(): Promise<number> {
  return getDb().ops.where('status').anyOf(UNSYNCED_STATUSES).count();
}
