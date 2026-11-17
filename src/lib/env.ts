export type EnvResult =
  | { ok: true; url: string; anonKey: string }
  | { ok: false; missing: string[] };

export function readEnv(source: Record<string, string | undefined>): EnvResult {
  const url = (source.VITE_SUPABASE_URL ?? '').trim();
  const anonKey = (source.VITE_SUPABASE_ANON_KEY ?? '').trim();
  const missing: string[] = [];
  if (!url) missing.push('VITE_SUPABASE_URL');
  if (!anonKey) missing.push('VITE_SUPABASE_ANON_KEY');
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true, url, anonKey };
}
