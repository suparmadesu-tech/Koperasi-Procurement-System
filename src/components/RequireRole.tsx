import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { canAccess, type Role } from '../lib/roles';
import { btnSecondary } from './ui';

export default function RequireRole({ role, children }: { role: Role; children: ReactNode }) {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  if (canAccess(state.role, role)) return <>{children}</>;
  return (
    <section className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold">Akses ditolak</h1>
      <p role="alert">Halaman ini hanya untuk Admin.</p>
      <Link to="/pengaturan" className={btnSecondary}>
        Kembali ke Pengaturan
      </Link>
    </section>
  );
}
