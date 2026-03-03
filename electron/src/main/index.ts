import { app, BrowserWindow } from 'electron'
import path from 'path'
import { getDatabase, closeDatabase } from './database/connection'
import { registerAllHandlers } from './ipc'
import { WindowManager } from './windows/WindowManager'

process.env.DIST_ELECTRON = path.join(__dirname, '..')
process.env.DIST = path.join(process.env.DIST_ELECTRON, '../dist')
process.env.VITE_PUBLIC = process.env.VITE_DEV_SERVER_URL
  ? path.join(process.env.DIST_ELECTRON, '../public')
  : process.env.DIST

// Initialize database and window manager
const db = getDatabase()
const windowManager = WindowManager.getInstance()

// Register all IPC handlers (including window management)
registerAllHandlers(db, windowManager)

app.whenReady().then(() => {
  windowManager.createMainWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  // On macOS, re-create the main window when dock icon is clicked
  if (BrowserWindow.getAllWindows().length === 0) {
    windowManager.createMainWindow()
  } else {
    // If main window exists but is hidden, show it
    const mainWin = windowManager.getMainWindow()
    if (mainWin) {
      mainWin.show()
      mainWin.focus()
    }
  }
})

app.on('before-quit', () => {
  closeDatabase()
})
