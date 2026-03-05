import { ipcMain } from 'electron'
import Database from 'better-sqlite3'
import { SessionDAO } from '../database/dao/SessionDAO'

export function registerSessionHandlers(db: Database.Database) {
  const sessionDAO = new SessionDAO(db)

  ipcMain.handle('sessions:list', (_e, projectId: string) =>
    sessionDAO.list(projectId)
  )

  ipcMain.handle('sessions:get', (_e, id: string) => sessionDAO.getById(id))

  ipcMain.handle(
    'sessions:create',
    (
      _e,
      data: {
        id: string
        projectId: string
        slug?: string
        startedAt?: string
        model?: string
        gitBranch?: string
        summary?: string
      }
    ) => sessionDAO.create(data)
  )

  ipcMain.handle(
    'sessions:update',
    (
      _e,
      id: string,
      data: {
        endedAt?: string
        summary?: string
        messageCount?: number
        toolUseCount?: number
        filesChanged?: string
        inputTokens?: number
        outputTokens?: number
        cacheCreationTokens?: number
        cacheReadTokens?: number
      }
    ) => sessionDAO.update(id, data)
  )

  ipcMain.handle('sessions:search', (_e, query: string) =>
    sessionDAO.searchFTS(query)
  )
}
