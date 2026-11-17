import { readEnv } from './lib/env';

export default function App() {
  const env = readEnv(import.meta.env);

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-5 py-10">
      <h1 className="text-2xl font-semibold">KPS</h1>
      <p className="text-base">Koperasi Procurement System. Kerangka proyek sudah berjalan.</p>
      {env.ok ? (
        <p className="rounded-md bg-white px-4 py-3 text-sm ring-1 ring-black/10">
          Konfigurasi Supabase terbaca. Halaman masuk dibuat di Bagian 2.
        </p>
      ) : (
        <p role="alert" className="rounded-md bg-white px-4 py-3 text-sm ring-1 ring-red-700/40">
          Konfigurasi belum lengkap. Isi variabel berikut: {env.missing.join(', ')}.
        </p>
      )}
    </main>
  );
}
