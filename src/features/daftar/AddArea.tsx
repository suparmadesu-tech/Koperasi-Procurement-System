import { useState, type ReactNode } from 'react'
import { btnPrimary, btnSecondary } from '../../components/ui'
import { AddCatalogForm } from './AddCatalogForm'
import { AddManualForm } from './AddManualForm'
import type { ListViewRow } from './listView'

type Mode = 'closed' | 'catalog' | 'manual'

function Panel({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="space-y-3 rounded-md bg-white p-4 ring-1 ring-black/20">
      <h2 id={id} className="font-semibold">
        {title}
      </h2>
      {children}
    </section>
  )
}

export function AddArea({
  workspaceId,
  rows,
  online,
  onFeedback,
}: {
  workspaceId: string
  rows: ListViewRow[]
  online: boolean
  onFeedback: (message: string) => void
}) {
  const [mode, setMode] = useState<Mode>('closed')
  const done = (message: string) => {
    setMode('closed')
    onFeedback(message)
  }

  if (mode === 'catalog') {
    return (
      <Panel id="panel-katalog" title="Tambah dari katalog">
        <AddCatalogForm
          workspaceId={workspaceId}
          rows={rows}
          online={online}
          onDone={done}
          onCancel={() => setMode('closed')}
        />
      </Panel>
    )
  }
  if (mode === 'manual') {
    return (
      <Panel id="panel-manual" title="Tambah barang manual">
        <AddManualForm workspaceId={workspaceId} online={online} onDone={done} onCancel={() => setMode('closed')} />
      </Panel>
    )
  }
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <button type="button" className={btnPrimary} onClick={() => setMode('catalog')} disabled={!online}>
          Tambah dari katalog
        </button>
        <button type="button" className={btnSecondary} onClick={() => setMode('manual')} disabled={!online}>
          Tambah barang manual
        </button>
      </div>
      {!online ? (
        <p className="text-sm">Anda sedang offline. Menambah, mengubah, dan menghapus barang memerlukan koneksi internet.</p>
      ) : null}
    </div>
  )
}
