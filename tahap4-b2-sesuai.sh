#!/usr/bin/env bash
# KPS Tahap 4 B2, patch kecil: jangan menyimpulkan "tanpa sesi" bila server belum pernah dapat diperiksa.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "BERHENTI: $1" >&2; exit 1; }
command -v python3 >/dev/null || fail "python3 tidak ditemukan"
F=src/features/belanja/BelanjaView.tsx
[ -f "$F" ] || fail "$F tidak ada; jalankan skrip B2 dulu"

python3 - "$F" <<'PY'
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()
edits = [
  ("    sync.lastSyncedAt === null &&\n    (sync.status === 'idle' || sync.status === 'syncing')",
   "    sync.lastSyncedAt === null"),
  ('            <p role="status">Memeriksa sesi belanja di server...</p>',
   "            <p role=\"status\">\n"
   "              {sync.status === 'offline' || sync.status === 'error'\n"
   "                ? 'Belum dapat memeriksa sesi belanja di server. Sesi aktif mungkin ada. Sambungkan internet lalu muat ulang.'\n"
   "                : 'Memeriksa sesi belanja di server...'}\n"
   "            </p>"),
]
for old, new in edits:
    n = s.count(old)
    if n != 1:
        sys.exit("BERHENTI: pola cocok %d kali (harus 1): %r" % (n, old))
    s = s.replace(old, new)
open(path, "w", encoding="utf-8").write(s)
PY

echo "Selesai. Jalankan: npx tsc --noEmit -p . && npx vitest run"
