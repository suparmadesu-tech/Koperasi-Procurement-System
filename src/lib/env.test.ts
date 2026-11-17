import { describe, expect, it } from 'vitest';
import { readEnv } from './env';

describe('readEnv', () => {
  it('melaporkan kedua variabel yang kosong', () => {
    expect(readEnv({})).toEqual({
      ok: false,
      missing: ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'],
    });
  });

  it('menganggap spasi saja sebagai kosong', () => {
    const r = readEnv({ VITE_SUPABASE_URL: '  ', VITE_SUPABASE_ANON_KEY: 'k' });
    expect(r).toEqual({ ok: false, missing: ['VITE_SUPABASE_URL'] });
  });

  it('mengembalikan nilai bila lengkap', () => {
    const r = readEnv({ VITE_SUPABASE_URL: 'https://x.supabase.co', VITE_SUPABASE_ANON_KEY: 'k' });
    expect(r).toEqual({ ok: true, url: 'https://x.supabase.co', anonKey: 'k' });
  });
});
