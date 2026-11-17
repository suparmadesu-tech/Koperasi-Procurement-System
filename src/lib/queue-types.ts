// Status antrean (SYNC-005): menunggu, sedang disinkronkan, berhasil, gagal.
export type OpStatus = 'pending' | 'syncing' | 'done' | 'failed';

// Penyebab status gagal. Hanya retry_exhausted yang menghalangi mulai sesi (FR-045).
export type FailureKind =
  | 'rejected' // ditolak server (SYNC-020 no. 2)
  | 'invalid' // KPS_INVALID_INPUT, KPS_UNKNOWN_OP, KPS_OP_ID_CONFLICT (no. 6)
  | 'forbidden' // otorisasi masih ditolak setelah sesi disegarkan (no. 3)
  | 'dependency' // operasi yang menjadi dependensi ditolak (SYNC-018)
  | 'retry_exhausted'; // jaringan atau galat tak terduga, batas percobaan habis (no. 5)

export type QueuedOp = {
  op_id: string;
  op_type: string;
  payload: Record<string, unknown>;
  status: OpStatus;
  attempts: number; // jumlah pengiriman yang dihitung (hanya saat online)
  depends_on: string | null;
  created_at: number; // epoch ms, naik tegas di dalam satu perangkat
  user_id: string;
  workspace_id: string;
  failure_kind: FailureKind | null;
  error_code: string | null;
  error_message: string | null;
  next_attempt_at: number | null;
  updated_at: number;
};

export type NewOpInput = {
  op_id?: string;
  op_type: string;
  payload: Record<string, unknown>;
  depends_on?: string | null;
  user_id: string;
  workspace_id: string;
};

// Belum tersimpan di server: dipakai peringatan saat keluar (FR-002).
export const UNSYNCED_STATUSES: OpStatus[] = ['pending', 'syncing', 'failed'];
