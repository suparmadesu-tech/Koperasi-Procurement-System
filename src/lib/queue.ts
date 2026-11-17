import { getDb, type KpsDb } from './db';
import type { NewOpInput, QueuedOp } from './queue-types';

export async function enqueueOp(input: NewOpInput, db: KpsDb = getDb()): Promise<QueuedOp> {
  return db.transaction('rw', db.ops, async () => {
    const last = await db.ops.orderBy('created_at').last();
    const now = Date.now();
    const createdAt = last && last.created_at >= now ? last.created_at + 1 : now;
    const op: QueuedOp = {
      op_id: input.op_id ?? crypto.randomUUID(),
      op_type: input.op_type,
      payload: input.payload,
      status: 'pending',
      attempts: 0,
      depends_on: input.depends_on ?? null,
      created_at: createdAt,
      user_id: input.user_id,
      workspace_id: input.workspace_id,
      failure_kind: null,
      error_code: null,
      error_message: null,
      next_attempt_at: null,
      updated_at: createdAt,
    };
    await db.ops.add(op);
    return op;
  });
}

// FR-045: menunggu, sedang disinkronkan, atau gagal karena jaringan atau galat tak
// terduga yang sudah melewati batas percobaan menghalangi mulai sesi. Operasi yang
// ditolak server tidak menghalangi (SYNC-003, SS-18).
export function opBlocksSessionStart(op: Pick<QueuedOp, 'status' | 'failure_kind'>): boolean {
  if (op.status === 'pending' || op.status === 'syncing') return true;
  return op.status === 'failed' && op.failure_kind === 'retry_exhausted';
}

export async function countBlockingOps(db: KpsDb = getDb()): Promise<number> {
  return db.ops.filter(opBlocksSessionStart).count();
}
