#!/usr/bin/env bash
set -euo pipefail

if [ -f package.json ]; then
  echo "package.json sudah ada. Jalankan di folder kosong." >&2
  exit 1
fi

mkdir -p src/lib public scripts

cat > package.json <<'EOF'
{
  "name": "kps",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview --host",
    "test": "vitest run",
    "icons": "node scripts/make-icons.mjs"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "decimal.js": "^10.4.3",
    "dexie": "^4.0.8",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.5",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.4",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.47",
    "tailwindcss": "^3.4.17",
    "typescript": "^5.6.2",
    "vite": "^6.0.0",
    "vite-plugin-pwa": "^0.21.1",
    "vitest": "^3.0.0"
  }
}
EOF

cat > .gitignore <<'EOF'
node_modules
dist
.env
.env.*
!.env.example
*.local
.vercel
coverage
EOF

cat > .env.example <<'EOF'
# Salin menjadi .env untuk pengembangan lokal. Jangan commit .env.
# Hanya URL project dan anon key (kunci publik) yang dipakai di frontend.
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "types": ["vite/client", "vite-plugin-pwa/client"]
  },
  "include": ["src"]
}
EOF

cat > vite.config.ts <<'EOF'
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['apple-touch-icon.png'],
      manifest: {
        name: 'Koperasi Procurement System',
        short_name: 'KPS',
        description: 'Catatan kebutuhan dan belanja koperasi.',
        lang: 'id',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        theme_color: '#0f5c4d',
        background_color: '#f6f5f1',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,svg,woff2}'],
        navigateFallback: 'index.html',
        cleanupOutdatedCaches: true,
      },
    }),
  ],
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
EOF

cat > postcss.config.js <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

cat > tailwind.config.js <<'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: { DEFAULT: '#0f5c4d', dark: '#0b4539' },
        paper: '#f6f5f1',
        ink: '#1f2421',
      },
    },
  },
  plugins: [],
};
EOF

cat > index.html <<'EOF'
<!doctype html>
<html lang="id">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <meta name="theme-color" content="#0f5c4d" />
    <link rel="icon" type="image/png" href="/icon-192.png" />
    <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
    <title>KPS</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

cat > public/_redirects <<'EOF'
/* /index.html 200
EOF

cat > vercel.json <<'EOF'
{
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
}
EOF

cat > scripts/make-icons.mjs <<'EOF'
// Ikon sementara: kotak hijau polos dengan persegi terang di tengah. Ganti dengan ikon asli.
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';

const table = Uint32Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = table[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function png(size) {
  const bg = [0x0f, 0x5c, 0x4d];
  const fg = [0xf6, 0xf5, 0xf1];
  const lo = Math.floor(size * 0.3);
  const hi = Math.floor(size * 0.7);
  const raw = Buffer.alloc((size * 3 + 1) * size);
  for (let y = 0; y < size; y++) {
    const row = y * (size * 3 + 1);
    raw[row] = 0;
    for (let x = 0; x < size; x++) {
      const inside = x >= lo && x < hi && y >= lo && y < hi;
      const px = inside ? fg : bg;
      raw[row + 1 + x * 3] = px[0];
      raw[row + 2 + x * 3] = px[1];
      raw[row + 3 + x * 3] = px[2];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

writeFileSync('public/icon-192.png', png(192));
writeFileSync('public/icon-512.png', png(512));
writeFileSync('public/apple-touch-icon.png', png(180));
console.log('Ikon sementara dibuat di public/.');
EOF

cat > src/vite-env.d.ts <<'EOF'
/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />
EOF

cat > src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html,
  body,
  #root {
    min-height: 100%;
  }
  body {
    @apply bg-paper text-ink antialiased;
    font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
    padding-top: env(safe-area-inset-top, 0px);
    padding-bottom: env(safe-area-inset-bottom, 0px);
  }
  :focus-visible {
    @apply outline outline-2 outline-offset-2 outline-brand;
  }
}
EOF

cat > src/lib/env.ts <<'EOF'
export type EnvResult =
  | { ok: true; url: string; anonKey: string }
  | { ok: false; missing: string[] };

export function readEnv(source: Record<string, string | undefined>): EnvResult {
  const url = (source.VITE_SUPABASE_URL ?? '').trim();
  const anonKey = (source.VITE_SUPABASE_ANON_KEY ?? '').trim();
  const missing: string[] = [];
  if (!url) missing.push('VITE_SUPABASE_URL');
  if (!anonKey) missing.push('VITE_SUPABASE_ANON_KEY');
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true, url, anonKey };
}
EOF

cat > src/lib/env.test.ts <<'EOF'
import { describe, expect, it } from 'vitest';
import { readEnv } from './env';

describe('readEnv', () => {
  it('melaporkan kedua variabel yang kosong', () => {
    expect(readEnv({})).toEqual({
      ok: false,
      missing: ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'],
    });
  });

  it('menganggap spasi saja sebagai kosong', () => {
    const r = readEnv({ VITE_SUPABASE_URL: '  ', VITE_SUPABASE_ANON_KEY: 'k' });
    expect(r).toEqual({ ok: false, missing: ['VITE_SUPABASE_URL'] });
  });

  it('mengembalikan nilai bila lengkap', () => {
    const r = readEnv({ VITE_SUPABASE_URL: 'https://x.supabase.co', VITE_SUPABASE_ANON_KEY: 'k' });
    expect(r).toEqual({ ok: true, url: 'https://x.supabase.co', anonKey: 'k' });
  });
});
EOF

cat > src/main.tsx <<'EOF'
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import App from './App';
import './index.css';

registerSW({ immediate: true });

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
EOF

cat > src/App.tsx <<'EOF'
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
EOF

npm install
node scripts/make-icons.mjs
echo "Selesai. Jalankan: npm run build && npm run test"
