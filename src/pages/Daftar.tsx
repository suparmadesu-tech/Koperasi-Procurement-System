import { useAuth } from '../auth/AuthProvider';
import { DaftarView } from '../features/daftar/DaftarView';

export default function Daftar() {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  return <DaftarView workspaceId={state.workspace.id} />;
}
