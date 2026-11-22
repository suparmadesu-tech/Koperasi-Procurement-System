import { countPendingOps } from '../../lib/pending-ops'
import { countBlockingOps } from '../../lib/queue'
import { checkEnd, checkStart } from './sessionGuards'

export const checkStartLive = () => checkStart(() => countBlockingOps())
export const checkEndLive = () => checkEnd(() => countPendingOps())
