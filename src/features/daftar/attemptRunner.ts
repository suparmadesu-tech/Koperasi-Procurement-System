import type { SubmitOptions } from './submitCore'
import type { ListOpResult, ListOpType } from './types'

type Payload = Record<string, unknown>
type Submit = (type: ListOpType, payload: Payload, options: SubmitOptions) => Promise<ListOpResult>
interface Attempt {
  opId: string
  type: ListOpType
  payload: Payload
}

// Satu percobaan yang gagal dengan retryable disimpan, lalu dikirim ulang dengan opId dan payload yang sama.
export function createAttemptRunner(submit: Submit, newId: () => string) {
  let attempt: Attempt | null = null

  async function send(a: Attempt): Promise<ListOpResult> {
    const r = await submit(a.type, a.payload, { opId: a.opId })
    attempt = !r.ok && r.retryable ? a : null
    return r
  }

  return {
    run: (type: ListOpType, payload: Payload): Promise<ListOpResult> => send({ opId: newId(), type, payload }),
    retry: async (): Promise<ListOpResult | null> => (attempt ? send(attempt) : null),
    discard: (): void => {
      attempt = null
    },
    hasPending: (): boolean => attempt !== null,
  }
}
