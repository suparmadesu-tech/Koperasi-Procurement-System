import { describe, expect, it } from 'vitest';
import { NAV_ITEMS, canAccess, filterByRole, isRole, roleLabel } from './roles';

describe('roles', () => {
  it('mengenali peran yang sah saja', () => {
    expect(isRole('admin')).toBe(true);
    expect(isRole('member')).toBe(true);
    expect(isRole('owner')).toBe(false);
    expect(isRole(null)).toBe(false);
  });

  it('memberi label bahasa Indonesia', () => {
    expect(roleLabel('admin')).toBe('Admin');
    expect(roleLabel('member')).toBe('Anggota');
  });

  it('Admin memiliki seluruh hak Anggota', () => {
    expect(canAccess('admin', 'admin')).toBe(true);
    expect(canAccess('admin', 'member')).toBe(true);
    expect(canAccess('member', 'member')).toBe(true);
    expect(canAccess('member', 'admin')).toBe(false);
    expect(canAccess('member', null)).toBe(true);
  });

  it('menyembunyikan menu khusus Admin dari Anggota', () => {
    const items = [
      { to: '/a', adminOnly: false },
      { to: '/b', adminOnly: true },
    ];
    expect(filterByRole(items, 'member')).toEqual([{ to: '/a', adminOnly: false }]);
    expect(filterByRole(items, 'admin')).toHaveLength(2);
  });

  it('menampilkan kelima menu utama untuk Anggota', () => {
    expect(filterByRole(NAV_ITEMS, 'member').map((i) => i.label)).toEqual([
      'Katalog',
      'Daftar',
      'Belanja',
      'Riwayat',
      'Pengaturan',
    ]);
  });
});
