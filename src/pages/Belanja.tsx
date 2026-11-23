import { useAuth } from '../auth/AuthProvider';
import { BelanjaView } from '../features/belanja/BelanjaView';

export default function Belanja() {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  return <BelanjaView workspaceId={state.workspace.id} />;
}
