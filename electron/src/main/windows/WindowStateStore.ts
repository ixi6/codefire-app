import fs from 'fs'
import path from 'path'
import { app } from 'electron'

export interface WindowState {
  x?: number
  y?: number
  width: number
  height: number
  isMaximized?: boolean
}

export interface WindowStateData {
  [key: string]: WindowState
}

/**
 * Persists window position/size to a JSON file in the user data directory.
 * Keys are 'main' for the main window or 'project:<id>' for project windows.
 */
export class WindowStateStore {
  private filePath: string
  private data: WindowStateData
  private saveTimer: ReturnType<typeof setTimeout> | null = null

  constructor(filePath?: string) {
    this.filePath = filePath ?? path.join(app.getPath('userData'), 'window-state.json')
    this.data = this.load()
  }

  get(key: string): WindowState | undefined {
    return this.data[key]
  }

  set(key: string, state: WindowState): void {
    this.data[key] = state
    this.scheduleSave()
  }

  delete(key: string): void {
    delete this.data[key]
    this.scheduleSave()
  }

  getAll(): WindowStateData {
    return { ...this.data }
  }

  private load(): WindowStateData {
    try {
      const raw = fs.readFileSync(this.filePath, 'utf-8')
      const parsed = JSON.parse(raw)
      if (typeof parsed === 'object' && parsed !== null) {
        return parsed as WindowStateData
      }
    } catch {
      // File doesn't exist or is corrupt — start fresh
    }
    return {}
  }

  /**
   * Debounce saves to avoid excessive disk writes during resize/move.
   */
  private scheduleSave(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
    }
    this.saveTimer = setTimeout(() => {
      this.saveNow()
      this.saveTimer = null
    }, 500)
  }

  saveNow(): void {
    try {
      const dir = path.dirname(this.filePath)
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true })
      }
      fs.writeFileSync(this.filePath, JSON.stringify(this.data, null, 2), 'utf-8')
    } catch {
      // Silently fail — window state is not critical
    }
  }
}
