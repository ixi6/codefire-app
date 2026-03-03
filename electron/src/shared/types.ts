// ─── IPC Channel Names ───────────────────────────────────────────────────────

export type ProjectChannel =
  | 'projects:list'
  | 'projects:get'
  | 'projects:getByPath'
  | 'projects:create'
  | 'projects:update'
  | 'projects:updateLastOpened'
  | 'projects:delete'

export type TaskChannel =
  | 'tasks:list'
  | 'tasks:listGlobal'
  | 'tasks:get'
  | 'tasks:create'
  | 'tasks:update'
  | 'tasks:delete'

export type TaskNoteChannel = 'taskNotes:list' | 'taskNotes:create'

export type NoteChannel =
  | 'notes:list'
  | 'notes:get'
  | 'notes:create'
  | 'notes:update'
  | 'notes:delete'
  | 'notes:search'

export type SessionChannel =
  | 'sessions:list'
  | 'sessions:get'
  | 'sessions:create'
  | 'sessions:update'
  | 'sessions:search'

export type ClientChannel = 'clients:list' | 'clients:get' | 'clients:create'

export type IpcChannel =
  | ProjectChannel
  | TaskChannel
  | TaskNoteChannel
  | NoteChannel
  | SessionChannel
  | ClientChannel

// ─── Electron API ────────────────────────────────────────────────────────────

export interface ElectronAPI {
  invoke: (channel: IpcChannel, ...args: unknown[]) => Promise<unknown>
  on: (channel: string, callback: (...args: unknown[]) => void) => () => void
  send: (channel: string, ...args: unknown[]) => void
}

declare global {
  interface Window {
    api: ElectronAPI
  }
}
