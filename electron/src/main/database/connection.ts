import Database from 'better-sqlite3'
import { getDatabasePath } from './paths'
import { Migrator } from './migrator'

let _db: Database.Database | null = null

export function getDatabase(): Database.Database {
  if (!_db) {
    const dbPath = getDatabasePath()
    _db = new Database(dbPath)
    _db.pragma('journal_mode = WAL')
    _db.pragma('busy_timeout = 5000')
    _db.pragma('foreign_keys = ON')

    const migrator = new Migrator(_db)
    migrator.migrate()
  }
  return _db
}

export function closeDatabase(): void {
  _db?.close()
  _db = null
}
