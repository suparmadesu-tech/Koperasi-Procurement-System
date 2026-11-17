import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import LogoutButton from '../components/LogoutButton';
import { btnSecondary } from '../components/ui';
import { roleLabel } from '../lib/roles';

export default function Pengaturan() {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;

  const rows: [string, string][] = [
    ['Nama', state.fullName ?? '-'],
    ['Email', state.user.email],
    ['Peran', roleLabel(state.role)],
    ['Workspace', state.workspace.name],
  ];

  return (
    <section className="flex flex-col gap-5">
      <h1 className="text-xl font-semibold">Pengaturan</h1>
      <dl className="divide-y divide-black/10 rounded-md bg-white ring-1 ring-black/10">
        {rows.map(([label, value]) => (
          <div key={label} className="flex flex-col gap-0.5 px-4 py-3">
            <dt className="text-sm text-ink/75">{label}</dt>
            <dd className="break-words text-base">{value}</dd>
          </div>
        ))}
      </dl>
      {state.role === 'admin' ? (
        <Link to="/pengaturan/admin" className={btnSecondary}>
          Pengelolaan Admin
        </Link>
      ) : null}
      <div className="flex flex-col gap-2">
        <LogoutButton />
        <p className="text-sm text-ink/75">
          Pemeriksaan perubahan yang belum tersimpan aktif setelah antrean operasi dibuat di Bagian 3.
        </p>
      </div>
    </section>
  );
}
