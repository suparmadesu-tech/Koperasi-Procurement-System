import 'fake-indexeddb/auto';
import { describe, expect, it } from 'vitest';
import { closeDb, getDb } from './db';
import { clearLocalData } from './local-data';
import type { QueuedOp } from './queue-types';

const op: QueuedOp = {
  op_id: 'x1',
  op_type: 'list_delete',
  payload: {},
  status: 'pending',
  attempts: 0,
  depends_on: null,
  created_at: 1,
  user_id: 'u1',
  workspace_id: 'w1',
  failure_kind: null,
  error_code: null,
  error_message: null,
  next_attempt_at: null,
  updated_at: 1,
};

describe('clearLocalData', () => {
  it('menutup koneksi Dexie yang terbuka lalu menghapus database', async () => {
    await getDb().ops.add(op);
    expect(await getDb().ops.count()).toBe(1);
    await clearLocalData();
    // instance baru, database baru yang kosong
    expect(await getDb().ops.count()).toBe(0);
  });

  it('tetap selesai bila belum ada instance Dexie', async () => {
    closeDb();
    await expect(clearLocalData()).resolves.toBeUndefined();
  });
});
