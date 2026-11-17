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
