// kps:admin-katalog
import { useAuth } from '../auth/AuthProvider'
import { AdminView } from '../features/katalog/AdminView'

export default function AdminArea() {
  const { state } = useAuth()
  if (state.status !== 'ready') return null
  if (state.role !== 'admin') {
    return <p className="text-sm text-slate-900">Halaman ini hanya untuk Admin.</p>
  }
  return <AdminView workspaceId={state.workspace.id} />
}
