#!/usr/bin/env bash
set -euo pipefail

if [ ! -f package.json ] || [ ! -f src/App.tsx ]; then
  echo "Jalankan dari akar proyek hasil Bagian 1." >&2
  exit 1
fi
if [ -d src/auth ]; then
  echo "src/auth sudah ada. Bagian 2 tampaknya sudah dijalankan." >&2
  exit 1
fi

mkdir -p src/auth src/components src/pages src/lib

cat > src/lib/constants.ts <<'EOF'
export const LOCAL_DB_NAME = 'kps-local';
export const LOCAL_STORAGE_PREFIX = 'kps.';
export const AUTH_STORAGE_KEY = 'kps.auth';
EOF

cat > src/lib/roles.ts <<'EOF'
export type Role = 'admin' | 'member';

export function isRole(value: unknown): value is Role {
  return value === 'admin' || value === 'member';
}

export function roleLabel(role: Role): string {
  return role === 'admin' ? 'Admin' : 'Anggota';
}

export function canAccess(role: Role, required: Role | null): boolean {
  if (required === null) return true;
  return required === 'member' || role === 'admin';
}

export type NavItem = { to: string; label: string; adminOnly: boolean };

export const NAV_ITEMS: NavItem[] = [
  { to: '/katalog', label: 'Katalog', adminOnly: false },
  { to: '/daftar', label: 'Daftar', adminOnly: false },
  { to: '/belanja', label: 'Belanja', adminOnly: false },
  { to: '/riwayat', label: 'Riwayat', adminOnly: false },
  { to: '/pengaturan', label: 'Pengaturan', adminOnly: false },
];

export function filterByRole<T extends { adminOnly: boolean }>(items: T[], role: Role): T[] {
  return items.filter((item) => !item.adminOnly || role === 'admin');
}
EOF

cat > src/lib/roles.test.ts <<'EOF'
import { describe, expect, it } from 'vitest';
import { NAV_ITEMS, canAccess, filterByRole, isRole, roleLabel } from './roles';

describe('roles', () => {
  it('mengenali peran yang sah saja', () => {
    expect(isRole('admin')).toBe(true);
    expect(isRole('member')).toBe(true);
    expect(isRole('owner')).toBe(false);
    expect(isRole(null)).toBe(false);
  });

  it('memberi label bahasa Indonesia', () => {
    expect(roleLabel('admin')).toBe('Admin');
    expect(roleLabel('member')).toBe('Anggota');
  });

  it('Admin memiliki seluruh hak Anggota', () => {
    expect(canAccess('admin', 'admin')).toBe(true);
    expect(canAccess('admin', 'member')).toBe(true);
    expect(canAccess('member', 'member')).toBe(true);
    expect(canAccess('member', 'admin')).toBe(false);
    expect(canAccess('member', null)).toBe(true);
  });

  it('menyembunyikan menu khusus Admin dari Anggota', () => {
    const items = [
      { to: '/a', adminOnly: false },
      { to: '/b', adminOnly: true },
    ];
    expect(filterByRole(items, 'member')).toEqual([{ to: '/a', adminOnly: false }]);
    expect(filterByRole(items, 'admin')).toHaveLength(2);
  });

  it('menampilkan kelima menu utama untuk Anggota', () => {
    expect(filterByRole(NAV_ITEMS, 'member').map((i) => i.label)).toEqual([
      'Katalog',
      'Daftar',
      'Belanja',
      'Riwayat',
      'Pengaturan',
    ]);
  });
});
EOF

cat > src/lib/auth-errors.ts <<'EOF'
export type AuthErrorLike =
  | { name?: string; message?: string; status?: number; code?: string }
  | null
  | undefined;

export function mapAuthError(err: AuthErrorLike): string {
  const message = err?.message ?? '';
  if (
    err?.name === 'AuthRetryableFetchError' ||
    err?.status === 0 ||
    /failed to fetch|network|load failed/i.test(message)
  ) {
    return 'Tidak ada koneksi internet. Login awal memerlukan koneksi.';
  }
  if (err?.code === 'invalid_credentials' || /invalid login credentials/i.test(message)) {
    return 'Email atau kata sandi salah.';
  }
  if (err?.status === 429 || err?.code === 'over_request_rate_limit') {
    return 'Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.';
  }
  if (err?.code === 'email_not_confirmed') {
    return 'Email akun ini belum dikonfirmasi. Hubungi pemilik proyek.';
  }
  return 'Gagal masuk. Coba lagi, atau hubungi pemilik proyek bila berulang.';
}
EOF

cat > src/lib/auth-errors.test.ts <<'EOF'
import { describe, expect, it } from 'vitest';
import { mapAuthError } from './auth-errors';

describe('mapAuthError', () => {
  it('jaringan terputus', () => {
    expect(mapAuthError({ name: 'AuthRetryableFetchError', status: 0 })).toContain('koneksi');
    expect(mapAuthError({ message: 'Failed to fetch' })).toContain('koneksi');
  });

  it('kredensial salah, lewat kode maupun pesan', () => {
    expect(mapAuthError({ code: 'invalid_credentials', status: 400 })).toBe(
      'Email atau kata sandi salah.',
    );
    expect(mapAuthError({ message: 'Invalid login credentials' })).toBe(
      'Email atau kata sandi salah.',
    );
  });

  it('batas permintaan', () => {
    expect(mapAuthError({ status: 429 })).toContain('Terlalu banyak');
  });

  it('email belum dikonfirmasi', () => {
    expect(mapAuthError({ code: 'email_not_confirmed' })).toContain('belum dikonfirmasi');
  });

  it('galat tak dikenal dan nilai kosong memakai pesan umum', () => {
    expect(mapAuthError({ message: 'aneh' })).toContain('Gagal masuk');
    expect(mapAuthError(null)).toContain('Gagal masuk');
  });
});
EOF

cat > src/lib/logout-flow.ts <<'EOF'
export type LogoutPlan = { needsConfirm: boolean; message: string };

export function planLogout(pending: number | null): LogoutPlan {
  if (pending === null) {
    return {
      needsConfirm: true,
      message:
        'Aplikasi tidak dapat memeriksa perubahan yang belum tersimpan di server. Jika tetap keluar, perubahan yang belum tersimpan akan hilang dari perangkat ini.',
    };
  }
  if (pending <= 0) return { needsConfirm: false, message: '' };
  return {
    needsConfirm: true,
    message: `Ada ${pending} perubahan yang belum tersimpan di server. Jika tetap keluar, perubahan itu akan hilang dari perangkat ini.`,
  };
}
EOF

cat > src/lib/logout-flow.test.ts <<'EOF'
import { describe, expect, it } from 'vitest';
import { planLogout } from './logout-flow';

describe('planLogout', () => {
  it('langsung keluar bila antrean kosong', () => {
    expect(planLogout(0)).toEqual({ needsConfirm: false, message: '' });
  });

  it('meminta konfirmasi dan menyebut jumlah perubahan', () => {
    const plan = planLogout(3);
    expect(plan.needsConfirm).toBe(true);
    expect(plan.message).toContain('3 perubahan');
    expect(plan.message).toContain('belum tersimpan di server');
  });

  it('meminta konfirmasi bila antrean tidak dapat diperiksa', () => {
    const plan = planLogout(null);
    expect(plan.needsConfirm).toBe(true);
    expect(plan.message).toContain('tidak dapat memeriksa');
  });
});
EOF

cat > src/lib/pending-ops.ts <<'EOF'
// TODO(Bagian 3): hitung operasi antrean Dexie yang berstatus menunggu, sedang
// disinkronkan, atau gagal (semuanya belum tersimpan di server). Sampai antrean
// ada, fungsi ini selalu 0.
export async function countPendingOps(): Promise<number> {
  return 0;
}
EOF

cat > src/lib/local-data.ts <<'EOF'
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
EOF

cat > src/lib/context-cache.ts <<'EOF'
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
EOF

cat > src/lib/supabase.ts <<'EOF'
import { createClient } from '@supabase/supabase-js';
import { AUTH_STORAGE_KEY } from './constants';
import { readEnv } from './env';

const env = readEnv(import.meta.env);

export const configError: string[] | null = env.ok ? null : env.missing;

export const supabase = env.ok
  ? createClient(env.url, env.anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        storageKey: AUTH_STORAGE_KEY,
      },
    })
  : null;
EOF

cat > src/auth/account-context.ts <<'EOF'
import type { SupabaseClient } from '@supabase/supabase-js';
import type { AppContext } from '../lib/context-cache';
import { isRole } from '../lib/roles';

type Workspace = { id: string; name: string };
type MemberRow = {
  role: string;
  workspace_id: string;
  workspaces: Workspace | Workspace[] | null;
};

export async function fetchContext(client: SupabaseClient, userId: string): Promise<AppContext> {
  const [profileRes, memberRes] = await Promise.all([
    client.from('profiles').select('full_name').eq('id', userId).maybeSingle(),
    client
      .from('workspace_members')
      .select('role, workspace_id, workspaces(id, name)')
      .eq('user_id', userId),
  ]);
  if (profileRes.error) throw profileRes.error;
  if (memberRes.error) throw memberRes.error;

  const row = ((memberRes.data ?? []) as unknown as MemberRow[])[0];
  if (!row) throw new Error('NO_WORKSPACE');
  if (!isRole(row.role)) throw new Error('BAD_ROLE');
  const ws = Array.isArray(row.workspaces) ? row.workspaces[0] : row.workspaces;
  if (!ws) throw new Error('NO_WORKSPACE');

  const profile = profileRes.data as { full_name: string | null } | null;
  return {
    fullName: profile?.full_name ?? null,
    workspaceId: ws.id,
    workspaceName: ws.name,
    role: row.role,
  };
}

export function describeContextError(e: unknown): string {
  const msg = e instanceof Error ? e.message : '';
  if (msg === 'NO_WORKSPACE') {
    return 'Akun ini belum terhubung ke workspace. Hubungi pemilik proyek.';
  }
  if (msg === 'BAD_ROLE') {
    return 'Peran akun tidak dikenali. Hubungi pemilik proyek.';
  }
  return 'Data akun tidak dapat dimuat. Periksa koneksi lalu coba lagi.';
}
EOF

cat > src/auth/AuthProvider.tsx <<'EOF'
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from 'react';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import { mapAuthError } from '../lib/auth-errors';
import { readContextCache, writeContextCache, type AppContext } from '../lib/context-cache';
import { clearLocalData } from '../lib/local-data';
import type { Role } from '../lib/roles';
import { configError, supabase } from '../lib/supabase';
import { describeContextError, fetchContext } from './account-context';

export type AuthState =
  | { status: 'loading' }
  | { status: 'config_error'; missing: string[] }
  | { status: 'signed_out' }
  | { status: 'context_error'; email: string; message: string }
  | {
      status: 'ready';
      user: { id: string; email: string };
      fullName: string | null;
      workspace: { id: string; name: string };
      role: Role;
    };

export type SignInResult = { ok: true } | { ok: false; message: string };

type AuthApi = {
  state: AuthState;
  signIn: (email: string, password: string) => Promise<SignInResult>;
  signOut: () => Promise<void>;
  retry: () => Promise<void>;
};

const AuthCtx = createContext<AuthApi | null>(null);

function readyState(user: { id: string; email: string }, ctx: AppContext): AuthState {
  return {
    status: 'ready',
    user,
    fullName: ctx.fullName,
    workspace: { id: ctx.workspaceId, name: ctx.workspaceName },
    role: ctx.role,
  };
}

async function resolveSession(
  client: SupabaseClient,
  session: Session | null,
  setState: Dispatch<SetStateAction<AuthState>>,
): Promise<void> {
  if (!session) {
    setState({ status: 'signed_out' });
    return;
  }
  const user = { id: session.user.id, email: session.user.email ?? '' };
  const cached = readContextCache(user.id);
  if (cached) setState(readyState(user, cached));
  try {
    const fresh = await fetchContext(client, user.id);
    writeContextCache(user.id, fresh);
    setState(readyState(user, fresh));
  } catch (e) {
    setState((prev) =>
      prev.status === 'ready' && prev.user.id === user.id
        ? prev
        : { status: 'context_error', email: user.email, message: describeContextError(e) },
    );
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>(
    configError ? { status: 'config_error', missing: configError } : { status: 'loading' },
  );

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    const guarded: Dispatch<SetStateAction<AuthState>> = (v) => {
      if (active) setState(v);
    };
    const { data } = client.auth.onAuthStateChange((event, session) => {
      if (event === 'TOKEN_REFRESHED') return;
      setTimeout(() => {
        void resolveSession(client, session, guarded);
      }, 0);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, []);

  const signIn = useCallback(async (email: string, password: string): Promise<SignInResult> => {
    if (!supabase) return { ok: false, message: 'Konfigurasi aplikasi belum lengkap.' };
    try {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (error) return { ok: false, message: mapAuthError(error) };
      setState({ status: 'loading' });
      return { ok: true };
    } catch (e) {
      return { ok: false, message: mapAuthError(e as Error) };
    }
  }, []);

  const signOut = useCallback(async () => {
    try {
      await supabase?.auth.signOut({ scope: 'local' });
    } catch {
      // sesi lokal tetap dibersihkan di bawah
    }
    await clearLocalData();
    setState({ status: 'signed_out' });
  }, []);

  const retry = useCallback(async () => {
    if (!supabase) return;
    setState({ status: 'loading' });
    const { data } = await supabase.auth.getSession();
    await resolveSession(supabase, data.session, setState);
  }, []);

  const value = useMemo(() => ({ state, signIn, signOut, retry }), [state, signIn, signOut, retry]);
  return <AuthCtx.Provider value={value}>{children}</AuthCtx.Provider>;
}

export function useAuth(): AuthApi {
  const ctx = useContext(AuthCtx);
  if (!ctx) throw new Error('useAuth harus dipakai di dalam AuthProvider');
  return ctx;
}
EOF

cat > src/components/ui.ts <<'EOF'
const base =
  'inline-flex min-h-12 cursor-pointer items-center justify-center rounded-md px-5 text-base font-medium disabled:cursor-not-allowed disabled:opacity-60';

export const btnPrimary = `${base} bg-brand text-white hover:bg-brand-dark active:bg-brand-dark`;
export const btnSecondary = `${base} bg-white text-ink ring-1 ring-black/25 hover:bg-black/5 active:bg-black/10`;
export const inputClass =
  'min-h-12 w-full rounded-md bg-white px-3 text-base ring-1 ring-black/30 placeholder:text-ink/50';
EOF

cat > src/components/StatusScreen.tsx <<'EOF'
import type { ReactNode } from 'react';

type Props = {
  title: string;
  message?: string;
  busy?: boolean;
  alert?: boolean;
  children?: ReactNode;
};

export default function StatusScreen({ title, message, busy, alert, children }: Props) {
  return (
    <main
      className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-5 py-10"
      aria-busy={busy ? true : undefined}
    >
      <h1 className="text-xl font-semibold">{title}</h1>
      {message ? (
        <p role={alert ? 'alert' : 'status'} className="text-base">
          {message}
        </p>
      ) : null}
      {children ? <div className="flex flex-col gap-3">{children}</div> : null}
    </main>
  );
}
EOF

cat > src/components/ConfirmDialog.tsx <<'EOF'
import { useEffect, useRef } from 'react';
import { btnPrimary, btnSecondary } from './ui';

type Props = {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
};

export default function ConfirmDialog(props: Props) {
  const { open, title, message, confirmLabel, cancelLabel, onConfirm, onCancel } = props;
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      aria-labelledby="confirm-title"
      onCancel={(e) => {
        e.preventDefault();
        onCancel();
      }}
      className="w-[calc(100%-2rem)] max-w-sm rounded-lg bg-white p-5 text-ink backdrop:bg-black/50"
    >
      <h2 id="confirm-title" className="text-lg font-semibold">
        {title}
      </h2>
      <p className="mt-2 text-base">{message}</p>
      <div className="mt-5 flex flex-col gap-3">
        <button type="button" className={btnSecondary} onClick={onCancel} autoFocus>
          {cancelLabel}
        </button>
        <button type="button" className={btnPrimary} onClick={onConfirm}>
          {confirmLabel}
        </button>
      </div>
    </dialog>
  );
}
EOF

cat > src/components/LogoutButton.tsx <<'EOF'
import { useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { planLogout } from '../lib/logout-flow';
import { countPendingOps } from '../lib/pending-ops';
import ConfirmDialog from './ConfirmDialog';
import { btnSecondary } from './ui';

export default function LogoutButton() {
  const { signOut } = useAuth();
  const [busy, setBusy] = useState(false);
  const [warning, setWarning] = useState<string | null>(null);

  async function onClick() {
    setBusy(true);
    let pending: number | null;
    try {
      pending = await countPendingOps();
    } catch {
      pending = null;
    }
    const plan = planLogout(pending);
    if (plan.needsConfirm) {
      setWarning(plan.message);
      setBusy(false);
      return;
    }
    await signOut();
  }

  async function confirmed() {
    setWarning(null);
    setBusy(true);
    await signOut();
  }

  return (
    <>
      <button type="button" className={btnSecondary} onClick={onClick} disabled={busy}>
        {busy ? 'Memproses...' : 'Keluar'}
      </button>
      <ConfirmDialog
        open={warning !== null}
        title="Keluar dari KPS?"
        message={warning ?? ''}
        confirmLabel="Tetap keluar"
        cancelLabel="Batal"
        onConfirm={confirmed}
        onCancel={() => setWarning(null)}
      />
    </>
  );
}
EOF

cat > src/components/Layout.tsx <<'EOF'
import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { NAV_ITEMS, filterByRole } from '../lib/roles';

export default function Layout({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  const items = filterByRole(NAV_ITEMS, state.role);

    return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 flex items-baseline justify-between gap-3 border-b border-black/10 bg-paper px-4 py-3">
        <span className="text-lg font-semibold">KPS</span>
        <span className="truncate text-sm text-ink/75">{state.workspace.name}</span>
      </header>
      <main className="mx-auto w-full max-w-md flex-1 px-4 pb-28 pt-5">{children}</main>
      <nav
        aria-label="Menu utama"
        className="fixed inset-x-0 bottom-0 z-10 border-t border-black/10 bg-white pb-[env(safe-area-inset-bottom)]"
      >
        <ul className="mx-auto grid max-w-md" style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}>
          {items.map((item) => (
            <li key={item.to}>
              <NavLink
                to={item.to}
                className={({ isActive }) =>
                  `flex min-h-14 items-center justify-center border-t-2 px-1 text-xs ${
                    isActive
                      ? 'border-brand font-semibold text-brand'
                      : 'border-transparent text-ink/75 hover:text-ink'
                  }`
                }
              >
                {item.label}
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>
    </div>
  );
}
EOF

cat > src/components/RequireRole.tsx <<'EOF'
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { canAccess, type Role } from '../lib/roles';
import { btnSecondary } from './ui';

export default function RequireRole({ role, children }: { role: Role; children: ReactNode }) {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  if (canAccess(state.role, role)) return <>{children}</>;
  return (
    <section className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold">Akses ditolak</h1>
      <p role="alert">Halaman ini hanya untuk Admin.</p>
      <Link to="/pengaturan" className={btnSecondary}>
        Kembali ke Pengaturan
      </Link>
    </section>
  );
}
EOF

cat > src/pages/Login.tsx <<'EOF'
import { useState, type FormEvent } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { btnPrimary, inputClass } from '../components/ui';

export default function Login() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    const result = await signIn(email, password);
    if (!result.ok) setError(result.message);
    setBusy(false);
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-6 px-5 py-10">
      <div>
        <p className="text-sm text-ink/75">Koperasi Procurement System</p>
        <h1 className="text-2xl font-semibold">Masuk</h1>
      </div>
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="email" className="text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            type="email"
            inputMode="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputClass}
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="password" className="text-sm font-medium">
            Kata sandi
          </label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={inputClass}
          />
        </div>
        {error ? (
          <p role="alert" className="rounded-md bg-white px-3 py-2 text-sm text-red-800 ring-1 ring-red-700/40">
            {error}
          </p>
        ) : null}
        <button type="submit" className={btnPrimary} disabled={busy}>
          {busy ? 'Memproses...' : 'Masuk'}
        </button>
      </form>
      <p className="text-sm text-ink/75">
        Akun dibuat oleh pemilik proyek. Tidak ada pendaftaran di aplikasi ini.
      </p>
    </main>
  );
}
EOF

cat > src/pages/Placeholder.tsx <<'EOF'
export default function Placeholder({ title, note }: { title: string; note: string }) {
  return (
    <section className="flex flex-col gap-3">
      <h1 className="text-xl font-semibold">{title}</h1>
      <p className="rounded-md bg-white px-4 py-3 text-base ring-1 ring-black/10">{note}</p>
    </section>
  );
}
EOF

cat > src/pages/Katalog.tsx <<'EOF'
import Placeholder from './Placeholder';

export default function Katalog() {
  return <Placeholder title="Katalog" note="Katalog barang belum tersedia. Dibuat di Tahap 2." />;
}
EOF

cat > src/pages/Daftar.tsx <<'EOF'
import Placeholder from './Placeholder';

export default function Daftar() {
  return <Placeholder title="Daftar" note="Daftar kebutuhan belum tersedia. Dibuat di Tahap 3." />;
}
EOF

cat > src/pages/Belanja.tsx <<'EOF'
import Placeholder from './Placeholder';

export default function Belanja() {
  return <Placeholder title="Belanja" note="Sesi belanja belum tersedia. Dibuat di Tahap 4." />;
}
EOF

cat > src/pages/Riwayat.tsx <<'EOF'
import Placeholder from './Placeholder';

export default function Riwayat() {
  return <Placeholder title="Riwayat" note="Riwayat belanja belum tersedia. Dibuat di Tahap 5." />;
}
EOF

cat > src/pages/AdminArea.tsx <<'EOF'
import Placeholder from './Placeholder';

export default function AdminArea() {
  return (
    <Placeholder
      title="Pengelolaan Admin"
      note="Pengelolaan kategori, satuan, dan ekspor data belum tersedia. Dibuat di Tahap 2 dan 5."
    />
  );
}
EOF

cat > src/pages/Pengaturan.tsx <<'EOF'
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import LogoutButton from '../components/LogoutButton';
import { btnSecondary } from '../components/ui';
import { roleLabel } from '../lib/roles';

export default function Pengaturan() {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;

  const rows: [string, string][] = [
    ['Nama', state.fullName ?? '-'],
    ['Email', state.user.email],
    ['Peran', roleLabel(state.role)],
    ['Workspace', state.workspace.name],
  ];

  return (
    <section className="flex flex-col gap-5">
      <h1 className="text-xl font-semibold">Pengaturan</h1>
      <dl className="divide-y divide-black/10 rounded-md bg-white ring-1 ring-black/10">
        {rows.map(([label, value]) => (
          <div key={label} className="flex flex-col gap-0.5 px-4 py-3">
            <dt className="text-sm text-ink/75">{label}</dt>
            <dd className="break-words text-base">{value}</dd>
          </div>
        ))}
      </dl>
      {state.role === 'admin' ? (
        <Link to="/pengaturan/admin" className={btnSecondary}>
          Pengelolaan Admin
        </Link>
      ) : null}
      <div className="flex flex-col gap-2">
        <LogoutButton />
        <p className="text-sm text-ink/75">
          Pemeriksaan perubahan yang belum tersimpan aktif setelah antrean operasi dibuat di Bagian 3.
        </p>
      </div>
    </section>
  );
}
EOF

cat > src/App.tsx <<'EOF'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth/AuthProvider';
import Layout from './components/Layout';
import LogoutButton from './components/LogoutButton';
import RequireRole from './components/RequireRole';
import StatusScreen from './components/StatusScreen';
import { btnPrimary } from './components/ui';
import AdminArea from './pages/AdminArea';
import Belanja from './pages/Belanja';
import Daftar from './pages/Daftar';
import Katalog from './pages/Katalog';
import Login from './pages/Login';
import Pengaturan from './pages/Pengaturan';
import Riwayat from './pages/Riwayat';

function Gate() {
  const { state, retry } = useAuth();

  switch (state.status) {
    case 'loading':
      return <StatusScreen title="KPS" message="Memuat..." busy />;
    case 'config_error':
      return (
        <StatusScreen
          title="Konfigurasi belum lengkap"
          message={`Isi variabel berikut: ${state.missing.join(', ')}.`}
          alert
        />
      );
    case 'signed_out':
      return <Login />;
    case 'context_error':
      return (
        <StatusScreen title="Akun tidak dapat dibuka" message={state.message} alert>
          <button type="button" className={btnPrimary} onClick={() => void retry()}>
            Coba lagi
          </button>
          <LogoutButton />
        </StatusScreen>
      );
    case 'ready':
      return (
        <Layout>
          <Routes>
            <Route path="/" element={<Navigate to="/daftar" replace />} />
            <Route path="/katalog" element={<Katalog />} />
            <Route path="/daftar" element={<Daftar />} />
            <Route path="/belanja" element={<Belanja />} />
            <Route path="/riwayat" element={<Riwayat />} />
            <Route path="/pengaturan" element={<Pengaturan />} />
            <Route
              path="/pengaturan/admin"
              element={
                <RequireRole role="admin">
                  <AdminArea />
                </RequireRole>
              }
            />
            <Route
              path="*"
              element={<p role="alert">Halaman tidak ditemukan.</p>}
            />
          </Routes>
        </Layout>
      );
  }
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Gate />
      </AuthProvider>
    </BrowserRouter>
  );
}
EOF

echo "Bagian 2 selesai. Jalankan: npm run build && npm run test"
