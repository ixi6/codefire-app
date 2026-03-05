import { ipcMain } from 'electron'
import Database from 'better-sqlite3'
import { TaskDAO } from '../database/dao/TaskDAO'
import { TaskNoteDAO } from '../database/dao/TaskNoteDAO'

export function registerTaskHandlers(db: Database.Database) {
  const taskDAO = new TaskDAO(db)
  const taskNoteDAO = new TaskNoteDAO(db)

  ipcMain.handle(
    'tasks:list',
    (_e, projectId: string, status?: string) =>
      taskDAO.list(projectId, status)
  )

  ipcMain.handle('tasks:listGlobal', (_e, status?: string) =>
    taskDAO.listGlobal(status)
  )

  ipcMain.handle('tasks:get', (_e, id: number) => taskDAO.getById(id))

  ipcMain.handle(
    'tasks:create',
    (
      _e,
      data: {
        projectId: string
        title: string
        description?: string
        priority?: number
        source?: string
        labels?: string[]
        isGlobal?: boolean
      }
    ) => taskDAO.create(data)
  )

  ipcMain.handle(
    'tasks:update',
    (
      _e,
      id: number,
      data: {
        title?: string
        description?: string
        status?: string
        priority?: number
        labels?: string[]
      }
    ) => taskDAO.update(id, data)
  )

  ipcMain.handle('tasks:delete', (_e, id: number) => taskDAO.delete(id))

  // Task notes
  ipcMain.handle('taskNotes:list', (_e, taskId: number) =>
    taskNoteDAO.list(taskId)
  )

  ipcMain.handle(
    'taskNotes:create',
    (
      _e,
      data: {
        taskId: number
        content: string
        source?: string
        sessionId?: string
      }
    ) => taskNoteDAO.create(data)
  )
}
