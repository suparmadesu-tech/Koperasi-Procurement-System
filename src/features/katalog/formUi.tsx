import { useId, type ReactNode } from 'react'

export const labelClass = 'mb-1 block text-sm font-medium text-slate-800'

export function Field({
  label,
  error,
  hint,
  children,
}: {
  label: string
  error?: string
  hint?: string
  children: (p: { id: string; describedBy: string | undefined; invalid: boolean }) => ReactNode
}) {
  const id = useId()
  const hintId = `${id}-hint`
  const errorId = `${id}-error`
  const describedBy = [hint ? hintId : '', error ? errorId : ''].filter(Boolean).join(' ') || undefined
  return (
    <div>
      <label htmlFor={id} className={labelClass}>
        {label}
      </label>
      {children({ id, describedBy, invalid: Boolean(error) })}
      {hint && (
        <p id={hintId} className="mt-1 text-sm text-slate-600">
          {hint}
        </p>
      )}
      {error && (
        <p id={errorId} className="mt-1 text-sm text-red-800">
          {error}
        </p>
      )}
    </div>
  )
}

export type Flash = { kind: 'ok' | 'error'; text: string } | null

export function FlashMessage({ flash }: { flash: Flash }) {
  if (!flash) return null
  return (
    <p
      role={flash.kind === 'error' ? 'alert' : 'status'}
      className={`text-sm ${flash.kind === 'error' ? 'text-red-800' : 'text-emerald-800'}`}
    >
      {flash.text}
    </p>
  )
}
