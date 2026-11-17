import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { NAV_ITEMS, filterByRole } from '../lib/roles';

export default function Layout({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  if (state.status !== 'ready') return null;
  const items = filterByRole(NAV_ITEMS, state.role);

   return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 flex items-baseline justify-between gap-3 border-b border-black/10 bg-paper px-4 py-3">
        <span className="text-lg font-semibold">KPS</span>
        <span className="truncate text-sm text-ink/75">{state.workspace.name}</span>
      </header>
      <main className="mx-auto w-full max-w-md flex-1 px-4 pb-28 pt-5">{children}</main>
      <nav
        aria-label="Menu utama"
        className="fixed inset-x-0 bottom-0 z-10 border-t border-black/10 bg-white pb-[env(safe-area-inset-bottom)]"
      >
        <ul className="mx-auto grid max-w-md" style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}>
          {items.map((item) => (
            <li key={item.to}>
              <NavLink
                to={item.to}
                className={({ isActive }) =>
                  `flex min-h-14 items-center justify-center border-t-2 px-1 text-xs ${
                    isActive
                      ? 'border-brand font-semibold text-brand'
                      : 'border-transparent text-ink/75 hover:text-ink'
                  }`
                }
              >
                {item.label}
              </NavLink>
            </li>
          ))}
        </ul>
      </nav>
    </div>
  );
}
