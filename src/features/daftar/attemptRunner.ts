import type { SubmitOptions } from './submitCore'
import type { ListOpResult } from './types'

type Payload = Record<string, unknown>
type Submit<T extends string> = (type: T, payload: Payload, options: SubmitOptions) => Promise<ListOpResult>
interface Attempt<T extends string> {
  opId: string
  type: T
  payload: Payload
}

// Satu percobaan yang gagal dengan retryable disimpan, lalu dikirim ulang dengan opId dan payload yang sama.
export function createAttemptRunner<T extends string = string>(submit: Submit<T>, newId: () => string) {
  let attempt: Attempt<T> | null = null

  async function send(a: Attempt<T>): Promise<ListOpResult> {
    const r = await submit(a.type, a.payload, { opId: a.opId })
    attempt = !r.ok && r.retryable ? a : null
    return r
  }

  return {
    run: (type: T, payload: Payload): Promise<ListOpResult> => send({ opId: newId(), type, payload }),
    retry: async (): Promise<ListOpResult | null> => (attempt ? send(attempt) : null),
    discard: (): void => {
      attempt = null
    },
    hasPending: (): boolean => attempt !== null,
  }
}
