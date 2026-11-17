import { LOCAL_STORAGE_PREFIX } from './constants';
import { isRole, type Role } from './roles';

export type AppContext = {
  fullName: string | null;
  workspaceId: string;
  workspaceName: string;
  role: Role;
};

const cacheKey = (userId: string) => `${LOCAL_STORAGE_PREFIX}ctx.${userId}`;

export function readContextCache(userId: string): AppContext | null {
  try {
    const raw = localStorage.getItem(cacheKey(userId));
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<AppContext>;
    if (typeof v.workspaceId !== 'string' || typeof v.workspaceName !== 'string') return null;
    if (!isRole(v.role)) return null;
    return {
      fullName: typeof v.fullName === 'string' ? v.fullName : null,
      workspaceId: v.workspaceId,
      workspaceName: v.workspaceName,
      role: v.role,
    };
  } catch {
    return null;
  }
}

export function writeContextCache(userId: string, ctx: AppContext): void {
  try {
    localStorage.setItem(cacheKey(userId), JSON.stringify(ctx));
  } catch {
    // penyimpanan penuh atau diblokir: aplikasi tetap jalan tanpa cache
  }
}
