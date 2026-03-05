import { ipcMain } from 'electron'
import Database from 'better-sqlite3'
import { ClientDAO } from '../database/dao/ClientDAO'

export function registerClientHandlers(db: Database.Database) {
  const clientDAO = new ClientDAO(db)

  ipcMain.handle('clients:list', () => clientDAO.list())

  ipcMain.handle('clients:get', (_e, id: string) => clientDAO.getById(id))

  ipcMain.handle(
    'clients:create',
    (_e, data: { name: string; color?: string }) => clientDAO.create(data)
  )
}
