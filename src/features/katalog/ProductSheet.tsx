import { useEffect, useId, useRef, type KeyboardEvent } from 'react'
import { btnSecondary } from '../../components/ui'
import { usePhotoUrl } from './photo'
import type { ProductRow } from './types'
import type { ProductView } from './viewModel'

const FOCUSABLE = 'button, [href], select, input, [tabindex]:not([tabindex="-1"])'

function PhotoBox({ photoPath, name }: { photoPath: string | null; name: string }) {
  const { state, retry, reportImageError } = usePhotoUrl(photoPath)
  const note =
    state.kind === 'none'
      ? 'Belum ada foto.'
      : state.kind === 'loading'
        ? 'Memuat foto...'
        : state.kind === 'offline'
          ? 'Foto tidak tersedia saat offline.'
          : state.kind === 'error'
            ? 'Foto gagal dimuat.'
            : null

  return (
    <div className="flex aspect-[4/3] w-full items-center justify-center bg-slate-100">
      {state.kind === 'ready' ? (
        <img
          src={state.url}
          alt={name}
          width={1600}
          height={1200}
          decoding="async"
          onError={reportImageError}
          className="h-full w-full object-contain"
        />
      ) : (
        <div className="flex flex-col items-center gap-3 px-4 text-center">
          <p role="status" className="text-sm text-slate-700">
            {note}
          </p>
          {(state.kind === 'offline' || state.kind === 'error') && (
            <button type="button" onClick={retry} className={btnSecondary}>
              Coba lagi
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export function ProductSheet({
  product,
  view,
  onClose,
}: {
  product: ProductRow
  view: ProductView
  onClose: () => void
}) {
  const titleId = useId()
  const panelRef = useRef<HTMLDivElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    closeRef.current?.focus()
    return () => {
      document.body.style.overflow = previousOverflow
      opener?.focus()
    }
  }, [])

  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    if (e.key === 'Escape') {
      e.stopPropagation()
      onClose()
      return
    }
    if (e.key !== 'Tab') return
    const nodes = panelRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE)
    if (!nodes || nodes.length === 0) return
    const first = nodes[0]
    const last = nodes[nodes.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault()
      first.focus()
    }
  }

  const fraction =
    view.allowFraction === null
      ? 'Belum diketahui'
      : view.allowFraction
        ? 'Boleh pecahan'
        : 'Hanya bilangan bulat'

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-black/50 sm:items-center sm:p-6"
      onKeyDown={onKeyDown}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className="max-h-[90dvh] w-full max-w-md overflow-y-auto rounded-t-xl bg-white pb-[max(1rem,env(safe-area-inset-bottom))] sm:rounded-lg sm:pb-4"
      >
        <PhotoBox photoPath={product.photo_path} name={product.name} />
        <div className="px-4 pt-4">
          <div className="flex items-start justify-between gap-3">
            <h2 id={titleId} className="break-words text-lg font-semibold text-slate-900">
              {product.name}
            </h2>
            {product.is_archived && (
              <span className="mt-1 shrink-0 rounded-sm border border-slate-500 px-1.5 text-xs text-slate-800">
                Diarsipkan
              </span>
            )}
          </div>

          <dl className="mt-4 grid grid-cols-[7rem_1fr] gap-x-3 gap-y-2 text-sm">
            <dt className="text-slate-600">Harga</dt>
            <dd className="tabular-nums text-slate-900">{view.priceText ?? 'Harga belum tersedia'}</dd>
            <dt className="text-slate-600">Kategori</dt>
            <dd className="break-words text-slate-900">
              {view.categoryName}
              {view.categoryArchived && ' (Diarsipkan)'}
            </dd>
            <dt className="text-slate-600">Satuan</dt>
            <dd className="break-words text-slate-900">
              {view.unitName}
              {view.unitArchived && ' (Diarsipkan)'}
            </dd>
            <dt className="text-slate-600">Jumlah</dt>
            <dd className="text-slate-900">{fraction}</dd>
          </dl>

          <button ref={closeRef} type="button" onClick={onClose} className={`${btnSecondary} mt-6 w-full`}>
            Tutup
          </button>
        </div>
      </div>
    </div>
  )
}
