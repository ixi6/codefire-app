import { ipcMain } from 'electron'
import Database from 'better-sqlite3'
import { NoteDAO } from '../database/dao/NoteDAO'

export function registerNoteHandlers(db: Database.Database) {
  const noteDAO = new NoteDAO(db)

  ipcMain.handle(
    'notes:list',
    (_e, projectId: string, pinnedOnly?: boolean, isGlobal?: boolean) =>
      noteDAO.list(projectId, pinnedOnly, isGlobal)
  )

  ipcMain.handle('notes:get', (_e, id: number) => noteDAO.getById(id))

  ipcMain.handle(
    'notes:create',
    (
      _e,
      data: {
        projectId: string
        title: string
        content?: string
        pinned?: boolean
        sessionId?: string
        isGlobal?: boolean
      }
    ) => noteDAO.create(data)
  )

  ipcMain.handle(
    'notes:update',
    (
      _e,
      id: number,
      data: {
        title?: string
        content?: string
        pinned?: boolean
      }
    ) => noteDAO.update(id, data)
  )

  ipcMain.handle('notes:delete', (_e, id: number) => noteDAO.delete(id))

  ipcMain.handle(
    'notes:search',
    (_e, projectId: string, query: string, isGlobal?: boolean) =>
      noteDAO.searchFTS(projectId, query, isGlobal)
  )
}
