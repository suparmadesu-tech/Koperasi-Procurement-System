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
