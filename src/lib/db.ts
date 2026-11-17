import Dexie, { type Table } from 'dexie';
import { LOCAL_DB_NAME } from './constants';
import type { QueuedOp } from './queue-types';

export class KpsDb extends Dexie {
  // "declare" agar bidang kelas tidak menimpa tabel buatan Dexie
  declare ops: Table<QueuedOp, string>;

  constructor() {
    super(LOCAL_DB_NAME);
    this.version(1).stores({
      ops: 'op_id, status, user_id, created_at, depends_on, [user_id+status]',
    });
  }
}

let instance: KpsDb | null = null;

export function getDb(): KpsDb {
  if (!instance) instance = new KpsDb();
  return instance;
}

// Menutup instance yang ada dan melupakannya. true bila instance memang ada.
export function closeDb(): boolean {
  if (!instance) return false;
  instance.close();
  instance = null;
  return true;
}
