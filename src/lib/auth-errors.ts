export type AuthErrorLike =
  | { name?: string; message?: string; status?: number; code?: string }
  | null
  | undefined;

export function mapAuthError(err: AuthErrorLike): string {
  const message = err?.message ?? '';
  if (
    err?.name === 'AuthRetryableFetchError' ||
    err?.status === 0 ||
    /failed to fetch|network|load failed/i.test(message)
  ) {
    return 'Tidak ada koneksi internet. Login awal memerlukan koneksi.';
  }
  if (err?.code === 'invalid_credentials' || /invalid login credentials/i.test(message)) {
    return 'Email atau kata sandi salah.';
  }
  if (err?.status === 429 || err?.code === 'over_request_rate_limit') {
    return 'Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.';
  }
  if (err?.code === 'email_not_confirmed') {
    return 'Email akun ini belum dikonfirmasi. Hubungi pemilik proyek.';
  }
  return 'Gagal masuk. Coba lagi, atau hubungi pemilik proyek bila berulang.';
}
