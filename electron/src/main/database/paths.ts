import path from 'path'
import os from 'os'
import fs from 'fs'

export function getDatabasePath(): string {
  let dir: string
  switch (process.platform) {
    case 'darwin':
      dir = path.join(os.homedir(), 'Library', 'Application Support', 'CodeFire')
      break
    case 'win32':
      dir = path.join(
        process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
        'CodeFire'
      )
      break
    default: // linux
      dir = path.join(os.homedir(), '.config', 'CodeFire')
  }
  fs.mkdirSync(dir, { recursive: true })
  return path.join(dir, 'codefire.db')
}
