import { createSyncController } from './syncFactory'
import { refreshSessions } from './sessionStore'

const controller = createSyncController({
  channelPrefix: 'kps-session',
  tables: ['shopping_sessions', 'shopping_session_items'],
  refresh: refreshSessions,
})

export const getSessionSyncState = controller.getState
export const subscribeSessionSyncState = controller.subscribe
export const acquireSessionSync = controller.acquire
export const requestSessionRefresh = controller.requestRefresh
