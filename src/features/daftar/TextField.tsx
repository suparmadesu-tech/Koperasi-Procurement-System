import { inputClass } from '../../components/ui'

export function TextField({
  id,
  label,
  value,
  onChange,
  error,
  hint,
  inputMode,
  multiline,
  readOnly,
}: {
  id: string
  label: string
  value: string
  onChange: (v: string) => void
  error?: string | undefined
  hint?: string | undefined
  inputMode?: 'text' | 'decimal' | 'numeric' | undefined
  multiline?: boolean | undefined
  readOnly?: boolean | undefined
}) {
  const describedBy = [hint ? `${id}-hint` : '', error ? `${id}-err` : ''].filter(Boolean).join(' ') || undefined
  return (
    <div className="space-y-1">
      <label htmlFor={id} className="block text-sm font-semibold">
        {label}
      </label>
      {multiline ? (
        <textarea
          id={id}
          rows={3}
          value={value}
          readOnly={readOnly}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          onChange={(e) => onChange(e.target.value)}
          className={`${inputClass} py-2`}
        />
      ) : (
        <input
          id={id}
          type="text"
          inputMode={inputMode}
          autoComplete="off"
          value={value}
          readOnly={readOnly}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        />
      )}
      {hint ? (
        <p id={`${id}-hint`} className="text-xs text-ink/75">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={`${id}-err`} className="text-sm text-red-900">
          {error}
        </p>
      ) : null}
    </div>
  )
}
