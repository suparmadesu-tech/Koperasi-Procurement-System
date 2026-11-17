import type { FailureKind } from './queue-types';

// Bentuk galat pengiriman yang sudah dinormalkan.
export type SendError = {
  network?: boolean;
  httpStatus?: number;
  sqlState?: string;
  kpsCode?: string;
  hint?: string;
  message?: string;
};

export type SendResult =
  | { kind: 'response'; status: string; code?: string | null }
  | { kind: 'error'; error: SendError };

export type ClassifyContext = { sessionRefreshed: boolean };

export type OutcomeAction =
  | { type: 'success' } // no. 1
  | { type: 'fail_rejected'; code: string | null } // no. 2
  | { type: 'fail_invalid'; code: string } // no. 6
  | { type: 'fail_forbidden' } // no. 3, setelah sesi disegarkan sekali
  | { type: 'refresh_and_resend'; reason: 'forbidden' | 'token_expired' } // no. 3 dan 4, tanpa menghabiskan percobaan
  | { type: 'needs_login' } // no. 4, refresh tidak menolong
  | { type: 'retry' }; // no. 5, dihitung menurut retry-schedule

const KPS_RE = /\bKPS_[A-Z_]+\b/;
const SQLSTATE_RE = /^[0-9A-Z]{5}$/;
const NETWORK_MESSAGE_RE =
  /failed to fetch|networkerror|network request failed|load failed|timed out|timeout/i;
const NETWORK_NAMES = ['AbortError', 'TimeoutError', 'AuthRetryableFetchError'];

function str(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined;
}

export function normalizeSendError(input: unknown, httpStatus?: number): SendError {
  const out: SendError = {};
  if (httpStatus !== undefined) out.httpStatus = httpStatus;
  if (input instanceof TypeError) {
    out.network = true;
    out.message = input.message;
    return out;
  }
  if (typeof input !== 'object' || input === null) return out;

  const raw = input as Record<string, unknown>;
  const name = str(raw.name);
  const message = str(raw.message);
  if (message) out.message = message;
  if ((name && NETWORK_NAMES.includes(name)) || (message && NETWORK_MESSAGE_RE.test(message))) {
    out.network = true;
  }

  const code = str(raw.code);
  if (code) {
    if (code.startsWith('KPS_')) out.kpsCode = code;
    else if (SQLSTATE_RE.test(code)) out.sqlState = code;
  }
  if (!out.kpsCode && message) {
    const m = KPS_RE.exec(message);
    if (m) out.kpsCode = m[0];
  }

  const hint = str(raw.hint);
  if (hint) out.hint = hint;
  if (out.httpStatus === undefined && typeof raw.status === 'number' && raw.status > 0) {
    out.httpStatus = raw.status;
  }
  return out;
}

function forbidden(ctx: ClassifyContext): OutcomeAction {
  return ctx.sessionRefreshed
    ? { type: 'fail_forbidden' }
    : { type: 'refresh_and_resend', reason: 'forbidden' };
}

function tokenExpired(ctx: ClassifyContext): OutcomeAction {
  return ctx.sessionRefreshed
    ? { type: 'needs_login' }
    : { type: 'refresh_and_resend', reason: 'token_expired' };
}

const INVALID_CODES = ['KPS_INVALID_INPUT', 'KPS_UNKNOWN_OP', 'KPS_OP_ID_CONFLICT'];
const RETRY_CODES = ['KPS_INTERNAL', 'KPS_DEPENDENCY_MISSING'];

export function classifyOutcome(result: SendResult, ctx: ClassifyContext): OutcomeAction {
  if (result.kind === 'response') {
    if (result.status === 'diterima') return { type: 'success' };
    if (result.status === 'ditolak') return { type: 'fail_rejected', code: result.code ?? null };
    return { type: 'retry' }; // jawaban tak dikenali dianggap tidak dikenali (no. 5)
  }

  const e = result.error;
  if (e.network) return { type: 'retry' };

  const kps = e.kpsCode;
  if (kps === 'KPS_FORBIDDEN') return forbidden(ctx);
  if (kps && INVALID_CODES.includes(kps)) return { type: 'fail_invalid', code: kps };
  if ((kps && RETRY_CODES.includes(kps)) || /RETRYABLE/i.test(e.hint ?? '')) {
    return { type: 'retry' };
  }

  if (e.sqlState === '42501') return forbidden(ctx);
  if (e.sqlState === '40001' || e.sqlState === '40P01') return { type: 'retry' };

  if (e.httpStatus === 401) return tokenExpired(ctx);
  if (e.httpStatus === 403) return forbidden(ctx);

  // 502, 503, 504, dan semua galat yang tidak dikenali
  return { type: 'retry' };
}

export function failureKindFor(action: OutcomeAction): FailureKind | null {
  switch (action.type) {
    case 'fail_rejected':
      return 'rejected';
    case 'fail_invalid':
      return 'invalid';
    case 'fail_forbidden':
      return 'forbidden';
    default:
      return null;
  }
}
