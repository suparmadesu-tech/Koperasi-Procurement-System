import { useEffect, useSyncExternalStore } from 'react'
import { clearFlowNotice, getFlowNotice, subscribeFlowNotice } from './flowNotice'

export function FlowNoticeBanner() {
  const notice = useSyncExternalStore(subscribeFlowNotice, getFlowNotice, getFlowNotice)
  // Pesan tidak boleh terbawa ke kunjungan berikutnya atau akun lain.
  useEffect(() => () => clearFlowNotice(), [])
  if (!notice) return null
  const tone = notice.tone === 'error' ? 'text-red-900 ring-red-800/60' : 'ring-black/25'
  return (
    <div
      role={notice.tone === 'error' ? 'alert' : 'status'}
      className={`flex items-start justify-between gap-3 rounded-md bg-white p-3 text-sm ring-1 ${tone}`}
    >
      <p className="min-w-0 break-words">{notice.text}</p>
      <button
        type="button"
        className="min-h-12 min-w-12 shrink-0 cursor-pointer px-3 underline"
        onClick={clearFlowNotice}
      >
        Tutup
      </button>
    </div>
  )
}
