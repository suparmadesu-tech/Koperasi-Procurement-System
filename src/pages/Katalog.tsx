// kps:katalog-baca
import { useAuth } from '../auth/AuthProvider'
import { KatalogView } from '../features/katalog/KatalogView'

export default function Katalog() {
  const { state } = useAuth()
  if (state.status !== 'ready') return null
  return <KatalogView workspaceId={state.workspace.id} isAdmin={state.role === 'admin'} />
}
