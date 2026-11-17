import { describe, expect, it } from 'vitest';
import { planLogout } from './logout-flow';

describe('planLogout', () => {
  it('langsung keluar bila antrean kosong', () => {
    expect(planLogout(0)).toEqual({ needsConfirm: false, message: '' });
  });

  it('meminta konfirmasi dan menyebut jumlah perubahan', () => {
    const plan = planLogout(3);
    expect(plan.needsConfirm).toBe(true);
    expect(plan.message).toContain('3 perubahan');
    expect(plan.message).toContain('belum tersimpan di server');
  });

  it('meminta konfirmasi bila antrean tidak dapat diperiksa', () => {
    const plan = planLogout(null);
    expect(plan.needsConfirm).toBe(true);
    expect(plan.message).toContain('tidak dapat memeriksa');
  });
});
