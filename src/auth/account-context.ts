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
