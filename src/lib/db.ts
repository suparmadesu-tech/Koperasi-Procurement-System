import Dexie, { type Table } from 'dexie';
import { LOCAL_DB_NAME } from './constants';
import type { QueuedOp } from './queue-types';
import type { ListItemRow } from '../features/daftar/types';
import type { SessionItemRow, SessionRow } from '../features/belanja/types';

export class KpsDb extends Dexie {
  // kps:katalog-v2: tabel katalog, tabel ops tidak berubah
  declare categories: import('dexie').Table<import('../features/katalog/types').CategoryRow, string>
  declare units: import('dexie').Table<import('../features/katalog/types').UnitRow, string>
  declare products: import('dexie').Table<import('../features/katalog/types').ProductRow, string>

  // "declare" agar bidang kelas tidak menimpa tabel buatan Dexie
  declare ops: Table<QueuedOp, string>;
  declare listItems: Table<ListItemRow, string>;
  declare sessions: Table<SessionRow, string>;
  declare sessionItems: Table<SessionItemRow, string>;

  constructor() {
    super(LOCAL_DB_NAME);
    this.version(1).stores({
      ops: 'op_id, status, user_id, created_at, depends_on, [user_id+status]',
    })
    this.version(2).stores({
      categories: 'id, workspace_id, name',
      units: 'id, workspace_id, name',
      products: 'id, workspace_id, category_id, unit_id, name',
    });
    this.version(3).stores({
      listItems: 'id, workspace_id, shopping_list_id, product_id',
    });
    this.version(4).stores({
      sessions: 'id, workspace_id, status',
      sessionItems: 'id, workspace_id, session_id',
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
