export type Role = 'admin' | 'member';

export function isRole(value: unknown): value is Role {
  return value === 'admin' || value === 'member';
}

export function roleLabel(role: Role): string {
  return role === 'admin' ? 'Admin' : 'Anggota';
}

export function canAccess(role: Role, required: Role | null): boolean {
  if (required === null) return true;
  return required === 'member' || role === 'admin';
}

export type NavItem = { to: string; label: string; adminOnly: boolean };

export const NAV_ITEMS: NavItem[] = [
  { to: '/katalog', label: 'Katalog', adminOnly: false },
  { to: '/daftar', label: 'Daftar', adminOnly: false },
  { to: '/belanja', label: 'Belanja', adminOnly: false },
  { to: '/riwayat', label: 'Riwayat', adminOnly: false },
  { to: '/pengaturan', label: 'Pengaturan', adminOnly: false },
];

export function filterByRole<T extends { adminOnly: boolean }>(items: T[], role: Role): T[] {
  return items.filter((item) => !item.adminOnly || role === 'admin');
}
