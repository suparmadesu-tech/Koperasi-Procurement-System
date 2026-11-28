import { useState } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { SessionAddCatalogForm } from './SessionAddCatalogForm'
import { SessionAddManualForm } from './SessionAddManualForm'

type Mode = 'closed' | 'catalog' | 'manual'
type Feedback = { text: string; tone: 'info' | 'error' }

export function AddToSession({
  workspaceId,
  sessionId,
  online,
}: {
  workspaceId: string
  sessionId: string
  online: boolean
}) {
  const [mode, setMode] = useState<Mode>('closed')
  const [feedback, setFeedback] = useState<Feedback | null>(null)

  const done = (text: string, tone: 'info' | 'error') => {
    setMode('closed')
    setFeedback({ text, tone })
  }
  const open = (next: Exclude<Mode, 'closed'>) => {
    setFeedback(null)
    setMode(next)
  }

  return (
    <section aria-labelledby="tambah-ke-sesi" className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id="tambah-ke-sesi" className="font-semibold">
        Tambah barang ke sesi
      </h2>

      {mode === 'closed' ? (
        <>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btnPrimary} onClick={() => open('catalog')} disabled={!online}>
              Tambah dari katalog
            </button>
            <button type="button" className={btnSecondary} onClick={() => open('manual')} disabled={!online}>
              Tambah barang manual
            </button>
          </div>
          {!online ? (
            <p className="text-sm">Anda sedang offline. Menambah barang ke sesi memerlukan koneksi internet.</p>
          ) : (
            <p className="text-xs text-ink/75">
              Barang yang ditambahkan langsung ke sesi tidak masuk daftar kebutuhan dan tidak mengubah estimasi awal
              sesi.
            </p>
          )}
        </>
      ) : mode === 'catalog' ? (
        <div className="space-y-3">
          <h3 className="font-semibold">Tambah dari katalog</h3>
          <SessionAddCatalogForm
            workspaceId={workspaceId}
            sessionId={sessionId}
            online={online}
            onDone={done}
            onCancel={() => setMode('closed')}
          />
        </div>
      ) : (
        <div className="space-y-3">
          <h3 className="font-semibold">Tambah barang manual</h3>
          <SessionAddManualForm
            workspaceId={workspaceId}
            sessionId={sessionId}
            online={online}
            onDone={done}
            onCancel={() => setMode('closed')}
          />
        </div>
      )}

      {feedback ? (
        <div
          role={feedback.tone === 'error' ? 'alert' : 'status'}
          className={`flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ${
            feedback.tone === 'error' ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
          }`}
        >
          <p className="min-w-0 break-words">{feedback.text}</p>
          <button
            type="button"
            className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
            onClick={() => setFeedback(null)}
          >
            Tutup
          </button>
        </div>
      ) : null}
    </section>
  )
}
