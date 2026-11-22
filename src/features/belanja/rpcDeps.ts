import type { SupabaseClient } from '@supabase/supabase-js'
import { supabase } from '../../lib/supabase'

export const sbClient = supabase as unknown as SupabaseClient | null

export async function refreshSupabaseSession(): Promise<boolean> {
  if (!sbClient) return false
  const { data, error } = await sbClient.auth.refreshSession()
  return !error && data.session !== null
}
