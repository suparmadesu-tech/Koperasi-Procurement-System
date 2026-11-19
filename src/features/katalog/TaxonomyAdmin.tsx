import { useState, type FormEvent } from 'react'
import { btnPrimary, btnSecondary, inputClass } from '../../components/ui'
import { createCategory, createUnit, updateCategory, updateUnit } from './catalogWrite'
import { Field, FlashMessage, type Flash } from './formUi'
import { compareByName } from './search'
import type { CategoryRow } from './types'
import { validateCategoryForm, validateUnitForm } from './validation'

type Kind = 'category' | 'unit'
type Row = CategoryRow & { allow_fraction?: boolean }

const WORDS = {
  category: { title: 'Kategori', add: 'Tambah kategori', added: 'Kategori ditambahkan.', saved: 'Kategori disimpan.' },
  unit: { title: 'Satuan', add: 'Tambah satuan', added: 'Satuan ditambahkan.', saved: 'Satuan disimpan.' },
} as const

export function TaxonomyAdmin({
  kind,
  workspaceId,
  rows,
  online,
}: {
  kind: Kind
  workspaceId: string
  rows: readonly Row[]
  online: boolean
}) {
  const words = WORDS[kind]
  const [addName, setAddName] = useState('')
  const [addFraction, setAddFraction] = useState(false)
  const [addError, setAddError] = useState<string | undefined>()
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [editFraction, setEditFraction] = useState(false)
  const [editError, setEditError] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [flash, setFlash] = useState<Flash>(null)

  // Mengembalikan pesan galat, atau null bila server menerima.
  async function submit(id: string | null, name: string, allowFraction: boolean): Promise<string | null> {
    if (kind === 'unit') {
      const v = validateUnitForm({ name, allowFraction })
      if (!v.ok) return v.errors.name ?? 'Isian tidak valid.'
      const r = id ? await updateUnit(workspaceId, id, v.value) : await createUnit(workspaceId, v.value)
      return r.ok ? null : r.error.message
    }
    const v = validateCategoryForm({ name })
    if (!v.ok) return v.errors.name ?? 'Isian tidak valid.'
    const r = id ? await updateCategory(workspaceId, id, v.value) : await createCategory(workspaceId, v.value)
    return r.ok ? null : r.error.message
  }

  async function onAdd(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    setBusy(true)
    setFlash(null)
    const error = await submit(null, addName, addFraction)
    setBusy(false)
    if (error) {
      setAddError(error)
      return
    }
    setAddError(undefined)
    setAddName('')
    setAddFraction(false)
    setFlash({ kind: 'ok', text: words.added })
  }

  async function onEdit(e: FormEvent) {
    e.preventDefault()
    if (busy || !editingId) return
    setBusy(true)
    setFlash(null)
    const error = await submit(editingId, editName, editFraction)
    setBusy(false)
    if (error) {
      setEditError(error)
      return
    }
    setEditingId(null)
    setEditError(undefined)
    setFlash({ kind: 'ok', text: words.saved })
  }

  async function toggleArchive(row: Row) {
    if (busy) return
    setBusy(true)
    setFlash(null)
    const patch = { is_archived: !row.is_archived }
    const r = kind === 'unit' ? await updateUnit(workspaceId, row.id, patch) : await updateCategory(workspaceId, row.id, patch)
    setBusy(false)
    setFlash(
      r.ok
        ? { kind: 'ok', text: row.is_archived ? 'Diaktifkan kembali.' : 'Diarsipkan.' }
        : { kind: 'error', text: r.error.message },
    )
  }

  function startEdit(row: Row) {
    setEditingId(row.id)
    setEditName(row.name)
    setEditFraction(Boolean(row.allow_fraction))
    setEditError(undefined)
    setFlash(null)
  }

  const sorted = [...rows].sort((a, b) => Number(a.is_archived) - Number(b.is_archived) || compareByName(a, b))
  const fractionBox = (checked: boolean, onChange: (v: boolean) => void) => (
    <label className="flex min-h-11 items-center gap-3 text-sm text-slate-900">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="h-5 w-5" />
      Boleh jumlah pecahan (misalnya 0,5)
    </label>
  )

  return (
    <section aria-label={words.title} className="space-y-6">
      <form onSubmit={onAdd} className="space-y-3 rounded-md border border-slate-300 p-4">
        <fieldset disabled={!online || busy} className="space-y-3">
          <Field label={`Nama ${words.title.toLowerCase()} baru`} error={addError}>
            {(p) => (
              <input
                id={p.id}
                value={addName}
                onChange={(e) => setAddName(e.target.value)}
                aria-invalid={p.invalid}
                aria-describedby={p.describedBy}
                autoComplete="off"
                className={inputClass}
              />
            )}
          </Field>
          {kind === 'unit' && fractionBox(addFraction, setAddFraction)}
          <button type="submit" className={btnPrimary}>
            {words.add}
          </button>
        </fieldset>
        <FlashMessage flash={flash} />
      </form>

      {sorted.length === 0 ? (
        <p className="text-sm text-slate-700">Belum ada {words.title.toLowerCase()}.</p>
      ) : (
        <ul className="divide-y divide-slate-200 border-y border-slate-200">
          {sorted.map((row) =>
            editingId === row.id ? (
              <li key={row.id} className="py-3">
                <form onSubmit={onEdit} className="space-y-3">
                  <fieldset disabled={!online || busy} className="space-y-3">
                    <Field label={`Nama ${words.title.toLowerCase()}`} error={editError}>
                      {(p) => (
                        <input
                          id={p.id}
                          value={editName}
                          onChange={(e) => setEditName(e.target.value)}
                          aria-invalid={p.invalid}
                          aria-describedby={p.describedBy}
                          autoComplete="off"
                          autoFocus
                          className={inputClass}
                        />
                      )}
                    </Field>
                    {kind === 'unit' && fractionBox(editFraction, setEditFraction)}
                    {kind === 'unit' && (
                      <p className="text-sm text-slate-600">
                        Perubahan ini hanya berlaku untuk input baru. Data lama tidak diubah.
                      </p>
                    )}
                    <div className="flex gap-3">
                      <button type="submit" className={btnPrimary}>
                        Simpan
                      </button>
                      <button type="button" onClick={() => setEditingId(null)} className={btnSecondary}>
                        Batal
                      </button>
                    </div>
                  </fieldset>
                </form>
              </li>
            ) : (
              <li key={row.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                <div className="min-w-0">
                  <p className="break-words font-medium text-slate-900">{row.name}</p>
                  <p className="text-sm text-slate-600">
                    {kind === 'unit' && (row.allow_fraction ? 'Boleh pecahan' : 'Hanya bilangan bulat')}
                    {kind === 'unit' && row.is_archived && ' / '}
                    {row.is_archived && 'Diarsipkan'}
                  </p>
                </div>
                <div className="flex gap-2">
                  <button type="button" disabled={!online || busy} onClick={() => startEdit(row)} className={btnSecondary}>
                    Ubah
                  </button>
                  <button
                    type="button"
                    disabled={!online || busy}
                    onClick={() => void toggleArchive(row)}
                    className={btnSecondary}
                  >
                    {row.is_archived ? 'Aktifkan' : 'Arsipkan'}
                  </button>
                </div>
              </li>
            ),
          )}
        </ul>
      )}
    </section>
  )
}
