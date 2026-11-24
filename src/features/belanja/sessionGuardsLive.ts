import { countBlockingOps } from '../../lib/queue'
import { checkEnd, checkStart } from './sessionGuards'

export const checkStartLive = () => checkStart(() => countBlockingOps())
// Operasi yang sudah ditolak server tidak dianggap belum tersimpan (SYNC-003), sama seperti saat mulai sesi.
export const checkEndLive = () => checkEnd(() => countBlockingOps())
