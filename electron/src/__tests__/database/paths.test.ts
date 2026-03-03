import { describe, it, expect } from 'vitest'
import { getDatabasePath } from '../../main/database/paths'

describe('getDatabasePath', () => {
  it('returns platform-appropriate path ending in codefire.db', () => {
    const dbPath = getDatabasePath()
    expect(dbPath).toMatch(/codefire\.db$/)
    expect(dbPath).toContain('CodeFire')
  })
})
