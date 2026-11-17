export type LogoutPlan = { needsConfirm: boolean; message: string };

export function planLogout(pending: number | null): LogoutPlan {
  if (pending === null) {
    return {
      needsConfirm: true,
      message:
        'Aplikasi tidak dapat memeriksa perubahan yang belum tersimpan di server. Jika tetap keluar, perubahan yang belum tersimpan akan hilang dari perangkat ini.',
    };
  }
  if (pending <= 0) return { needsConfirm: false, message: '' };
  return {
    needsConfirm: true,
    message: `Ada ${pending} perubahan yang belum tersimpan di server. Jika tetap keluar, perubahan itu akan hilang dari perangkat ini.`,
  };
}
