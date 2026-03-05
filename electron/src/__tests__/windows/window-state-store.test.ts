import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import fs from 'fs'
import path from 'path'
import os from 'os'

// Mock the electron app module before importing WindowStateStore
vi.mock('electron', () => ({
  app: {
    getPath: vi.fn(() => os.tmpdir()),
  },
  BrowserWindow: vi.fn(),
  screen: {
    getAllDisplays: vi.fn(() => [
      { bounds: { x: 0, y: 0, width: 1920, height: 1080 } },
    ]),
  },
}))

import { WindowStateStore } from '../../main/windows/WindowStateStore'

describe('WindowStateStore', () => {
  let storePath: string
  let store: WindowStateStore

  beforeEach(() => {
    storePath = path.join(
      os.tmpdir(),
      `test-window-state-${Date.now()}-${Math.random().toString(36).slice(2)}.json`
    )
    store = new WindowStateStore(storePath)
  })

  afterEach(() => {
    try {
      fs.unlinkSync(storePath)
    } catch {
      // ignore
    }
  })

  describe('get/set', () => {
    it('returns undefined for unknown key', () => {
      expect(store.get('nonexistent')).toBeUndefined()
    })

    it('stores and retrieves window state', () => {
      store.set('main', { x: 100, y: 200, width: 1400, height: 900 })
      const state = store.get('main')
      expect(state).toEqual({ x: 100, y: 200, width: 1400, height: 900 })
    })

    it('stores state for multiple keys', () => {
      store.set('main', { width: 1400, height: 900 })
      store.set('project:abc', { x: 50, y: 50, width: 1200, height: 850 })

      expect(store.get('main')).toEqual({ width: 1400, height: 900 })
      expect(store.get('project:abc')).toEqual({ x: 50, y: 50, width: 1200, height: 850 })
    })

    it('overwrites existing state for same key', () => {
      store.set('main', { width: 1400, height: 900 })
      store.set('main', { x: 10, y: 20, width: 1600, height: 1000 })

      expect(store.get('main')).toEqual({ x: 10, y: 20, width: 1600, height: 1000 })
    })
  })

  describe('delete', () => {
    it('removes a stored key', () => {
      store.set('main', { width: 1400, height: 900 })
      store.delete('main')
      expect(store.get('main')).toBeUndefined()
    })

    it('is a no-op for nonexistent key', () => {
      expect(() => store.delete('nonexistent')).not.toThrow()
    })
  })

  describe('getAll', () => {
    it('returns a copy of all state', () => {
      store.set('main', { width: 1400, height: 900 })
      store.set('project:abc', { width: 1200, height: 850 })

      const all = store.getAll()
      expect(Object.keys(all)).toHaveLength(2)
      expect(all['main']).toEqual({ width: 1400, height: 900 })
      expect(all['project:abc']).toEqual({ width: 1200, height: 850 })
    })

    it('returns a copy, not a reference', () => {
      store.set('main', { width: 1400, height: 900 })
      const all = store.getAll()
      all['main'] = { width: 999, height: 999 }
      expect(store.get('main')).toEqual({ width: 1400, height: 900 })
    })
  })

  describe('persistence', () => {
    it('saves to disk via saveNow and reloads', () => {
      store.set('main', { x: 100, y: 200, width: 1400, height: 900 })
      store.saveNow()

      // Create a new store reading the same file
      const store2 = new WindowStateStore(storePath)
      expect(store2.get('main')).toEqual({ x: 100, y: 200, width: 1400, height: 900 })
    })

    it('handles corrupt JSON gracefully', () => {
      fs.writeFileSync(storePath, 'not valid json{{{', 'utf-8')
      const store2 = new WindowStateStore(storePath)
      expect(store2.get('main')).toBeUndefined()
      expect(store2.getAll()).toEqual({})
    })

    it('handles missing file gracefully', () => {
      const missingPath = path.join(os.tmpdir(), 'nonexistent-window-state.json')
      const store2 = new WindowStateStore(missingPath)
      expect(store2.getAll()).toEqual({})
    })
  })

  describe('isMaximized', () => {
    it('stores and retrieves isMaximized flag', () => {
      store.set('main', { x: 0, y: 0, width: 1920, height: 1080, isMaximized: true })
      const state = store.get('main')
      expect(state?.isMaximized).toBe(true)
    })
  })
})
