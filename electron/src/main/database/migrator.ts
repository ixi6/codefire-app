import Database from 'better-sqlite3'
import { migrations as defaultMigrations } from './migrations'

export interface Migration {
  version: number
  name: string
  up: (db: Database.Database) => void
}

export class Migrator {
  private migrations: Migration[]

  constructor(
    private db: Database.Database,
    migrations?: Migration[]
  ) {
    this.migrations = migrations ?? defaultMigrations
  }

  migrate(): void {
    this.db.exec(
      'CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)'
    )

    const row = this.db
      .prepare('SELECT version FROM schema_version')
      .get() as { version: number } | undefined
    const currentVersion = row?.version ?? 0

    if (!row) {
      this.db.prepare('INSERT INTO schema_version (version) VALUES (0)').run()
    }

    for (const migration of this.migrations) {
      if (migration.version > currentVersion) {
        this.db.transaction(() => {
          migration.up(this.db)
          this.db
            .prepare('UPDATE schema_version SET version = ?')
            .run(migration.version)
        })()
      }
    }
  }

  getCurrentVersion(): number {
    try {
      const row = this.db
        .prepare('SELECT version FROM schema_version')
        .get() as { version: number } | undefined
      return row?.version ?? 0
    } catch {
      return 0
    }
  }
}
