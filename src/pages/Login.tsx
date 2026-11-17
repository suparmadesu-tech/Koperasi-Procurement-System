import { useState, type FormEvent } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { btnPrimary, inputClass } from '../components/ui';

export default function Login() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    const result = await signIn(email, password);
    if (!result.ok) setError(result.message);
    setBusy(false);
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-6 px-5 py-10">
      <div>
        <p className="text-sm text-ink/75">Koperasi Procurement System</p>
        <h1 className="text-2xl font-semibold">Masuk</h1>
      </div>
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="email" className="text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            type="email"
            inputMode="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputClass}
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="password" className="text-sm font-medium">
            Kata sandi
          </label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={inputClass}
          />
        </div>
        {error ? (
          <p role="alert" className="rounded-md bg-white px-3 py-2 text-sm text-red-800 ring-1 ring-red-700/40">
            {error}
          </p>
        ) : null}
        <button type="submit" className={btnPrimary} disabled={busy}>
          {busy ? 'Memproses...' : 'Masuk'}
        </button>
      </form>
      <p className="text-sm text-ink/75">
        Akun dibuat oleh pemilik proyek. Tidak ada pendaftaran di aplikasi ini.
      </p>
    </main>
  );
}
