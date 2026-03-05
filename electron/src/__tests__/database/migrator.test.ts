import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import Database from 'better-sqlite3'
import { Migrator } from '../../main/database/migrator'
import type { Migration } from '../../main/database/migrator'
import fs from 'fs'
import path from 'path'
import os from 'os'

describe('Migrator', () => {
  let db: Database.Database
  let dbPath: string

  beforeEach(() => {
    dbPath = path.join(
      os.tmpdir(),
      `test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    )
    db = new Database(dbPath)
    db.pragma('journal_mode = WAL')
  })

  afterEach(() => {
    db.close()
    try {
      fs.unlinkSync(dbPath)
    } catch {
      // ignore cleanup errors
    }
  })

  it('creates schema_version table on first run', () => {
    const migrator = new Migrator(db)
    migrator.migrate()
    const row = db.prepare('SELECT version FROM schema_version').get() as {
      version: number
    }
    expect(row.version).toBeGreaterThanOrEqual(0)
  })

  it('is idempotent — running twice does not error', () => {
    const migrator = new Migrator(db)
    migrator.migrate()
    migrator.migrate() // should not throw
    const row = db.prepare('SELECT version FROM schema_version').get() as {
      version: number
    }
    expect(row.version).toBeGreaterThanOrEqual(0)
  })

  it('tracks current version', () => {
    const migrator = new Migrator(db)
    migrator.migrate()
    expect(migrator.getCurrentVersion()).toBeGreaterThanOrEqual(0)
  })

  it('returns 0 for fresh database', () => {
    const migrator = new Migrator(db)
    expect(migrator.getCurrentVersion()).toBe(0)
  })

  it('applies migrations in order', () => {
    const migrations: Migration[] = [
      {
        version: 1,
        name: 'create_users',
        up: (d) => {
          d.exec('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)')
        },
      },
      {
        version: 2,
        name: 'add_email',
        up: (d) => {
          d.exec('ALTER TABLE users ADD COLUMN email TEXT')
        },
      },
    ]

    const migrator = new Migrator(db, migrations)
    migrator.migrate()

    expect(migrator.getCurrentVersion()).toBe(2)

    // Verify the tables and columns exist
    const info = db.prepare('PRAGMA table_info(users)').all() as Array<{
      name: string
    }>
    const columnNames = info.map((col) => col.name)
    expect(columnNames).toContain('id')
    expect(columnNames).toContain('name')
    expect(columnNames).toContain('email')
  })

  it('only applies new migrations on subsequent runs', () => {
    const migration1: Migration = {
      version: 1,
      name: 'create_items',
      up: (d) => {
        d.exec('CREATE TABLE items (id INTEGER PRIMARY KEY)')
      },
    }

    // First run: apply migration 1
    const migrator1 = new Migrator(db, [migration1])
    migrator1.migrate()
    expect(migrator1.getCurrentVersion()).toBe(1)

    // Second run: add migration 2
    const migration2: Migration = {
      version: 2,
      name: 'add_items_name',
      up: (d) => {
        d.exec('ALTER TABLE items ADD COLUMN name TEXT')
      },
    }

    const migrator2 = new Migrator(db, [migration1, migration2])
    migrator2.migrate()
    expect(migrator2.getCurrentVersion()).toBe(2)
  })
})
