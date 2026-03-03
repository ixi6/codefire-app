import Database from 'better-sqlite3'
import { registerProjectHandlers } from './project-handlers'
import { registerTaskHandlers } from './task-handlers'
import { registerNoteHandlers } from './note-handlers'
import { registerSessionHandlers } from './session-handlers'
import { registerClientHandlers } from './client-handlers'
import { registerWindowHandlers } from './window-handlers'
import type { WindowManager } from '../windows/WindowManager'

export function registerAllHandlers(db: Database.Database, windowManager?: WindowManager) {
  registerProjectHandlers(db)
  registerTaskHandlers(db)
  registerNoteHandlers(db)
  registerSessionHandlers(db)
  registerClientHandlers(db)
  if (windowManager) {
    registerWindowHandlers(windowManager)
  }
}
