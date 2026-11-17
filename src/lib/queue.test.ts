import 'fake-indexeddb/auto';
import { beforeEach, describe, expect, it } from 'vitest';
import { getDb } from './db';
import { countPendingOps } from './pending-ops';
import { countBlockingOps, enqueueOp, opBlocksSessionStart } from './queue';
import type { FailureKind, OpStatus, QueuedOp } from './queue-types';

function makeOp(
  op_id: string,
  status: OpStatus,
  failure_kind: FailureKind | null = null,
): QueuedOp {
  return {
    op_id,
    op_type: 'list_set_quantity',
    payload: {},
    status,
    attempts: 0,
    depends_on: null,
    created_at: Date.now(),
    user_id: 'u1',
    workspace_id: 'w1',
    failure_kind,
    error_code: null,
    error_message: null,
    next_attempt_at: null,
    updated_at: Date.now(),
  };
}

beforeEach(async () => {
  await getDb().ops.clear();
});

describe('enqueueOp', () => {
  it('membuat operasi berstatus pending dengan UUID dan nilai awal', async () => {
    const op = await enqueueOp({
      op_type: 'list_add_manual',
      payload: { name: 'Gula' },
      user_id: 'u1',
      workspace_id: 'w1',
    });
    expect(op.op_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(op).toMatchObject({ status: 'pending', attempts: 0, depends_on: null });
    expect(await getDb().ops.get(op.op_id)).toEqual(op);
  });

  it('created_at naik tegas walau dibuat pada milidetik yang sama', async () => {
    const a = await enqueueOp({ op_type: 'x', payload: {}, user_id: 'u1', workspace_id: 'w1' });
    const b = await enqueueOp({ op_type: 'x', payload: {}, user_id: 'u1', workspace_id: 'w1' });
    expect(b.created_at).toBeGreaterThan(a.created_at);
  });

  it('menyimpan depends_on dan menerima op_id dari pemanggil', async () => {
    const op = await enqueueOp({
      op_id: '11111111-1111-4111-8111-111111111111',
      op_type: 'list_set_photo',
      payload: {},
      depends_on: '22222222-2222-4222-8222-222222222222',
      user_id: 'u1',
      workspace_id: 'w1',
    });
    expect(op.op_id).toBe('11111111-1111-4111-8111-111111111111');
    expect(op.depends_on).toBe('22222222-2222-4222-8222-222222222222');
  });
});

describe('countPendingOps (peringatan keluar, FR-002)', () => {
  it('0 bila antrean kosong', async () => {
    expect(await countPendingOps()).toBe(0);
  });

  it('menghitung menunggu, sedang disinkronkan, dan gagal; berhasil tidak', async () => {
    await getDb().ops.bulkAdd([
      makeOp('a', 'pending'),
      makeOp('b', 'syncing'),
      makeOp('c', 'failed', 'rejected'),
      makeOp('d', 'failed', 'retry_exhausted'),
      makeOp('e', 'done'),
    ]);
    expect(await countPendingOps()).toBe(4);
  });
});

describe('mulai sesi: operasi yang menghalangi (FR-045, SS-18, OF-14)', () => {
  it.each([
    ['pending', null, true],
    ['syncing', null, true],
    ['failed', 'retry_exhausted', true],
    ['failed', 'rejected', false],
    ['failed', 'invalid', false],
    ['failed', 'forbidden', false],
    ['failed', 'dependency', false],
    ['done', null, false],
  ] as [OpStatus, FailureKind | null, boolean][])('%s / %s menghalangi: %s', (status, kind, expected) => {
    expect(opBlocksSessionStart({ status, failure_kind: kind })).toBe(expected);
  });

  it('antrean hanya berisi operasi yang ditolak tidak menghalangi (SS-18)', async () => {
    await getDb().ops.bulkAdd([makeOp('a', 'failed', 'rejected'), makeOp('b', 'done')]);
    expect(await countBlockingOps()).toBe(0);
  });

  it('operasi gagal batas percobaan menghalangi sampai dibuang (OF-14)', async () => {
    await getDb().ops.add(makeOp('a', 'failed', 'retry_exhausted'));
    expect(await countBlockingOps()).toBe(1);
    await getDb().ops.delete('a');
    expect(await countBlockingOps()).toBe(0);
  });
});
