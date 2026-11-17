import Dexie from 'dexie';
import { LOCAL_DB_NAME, LOCAL_STORAGE_PREFIX } from './constants';
import { closeDb } from './db';

const DELETE_TIMEOUT_MS = 3000;

async function deleteWithDexie(): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<void>((resolve) => {
    timer = setTimeout(resolve, DELETE_TIMEOUT_MS);
  });
  try {
    await Promise.race([Dexie.delete(LOCAL_DB_NAME).catch(() => undefined), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export function clearLocalData(): Promise<void> {
  try {
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key && key.startsWith(LOCAL_STORAGE_PREFIX)) keys.push(key);
    }
    keys.forEach((key) => localStorage.removeItem(key));
  } catch {
    // localStorage diblokir: tidak ada yang dapat dihapus
  }
  if (closeDb()) return deleteWithDexie();
  return new Promise((resolve) => {
    try {
      const req = indexedDB.deleteDatabase(LOCAL_DB_NAME);
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    } catch {
      resolve();
    }
  });
}
