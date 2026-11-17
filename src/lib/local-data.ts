import { LOCAL_DB_NAME, LOCAL_STORAGE_PREFIX } from './constants';

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
