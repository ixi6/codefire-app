# Electron Phase 2 — Images, Recordings, Browser Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the remaining 3 tabs (Images, Recordings, Browser) to reach full feature parity with the Swift app.

**Architecture:** Each tab follows the established pattern: DAO → IPC handlers → types.ts channels → api.ts facade → View + Components → ProjectLayout routing. Images uses existing `generatedImages` DB table. Recordings uses Web Audio API + OpenAI Whisper. Browser uses Electron `<webview>` with custom DevTools panels.

**Tech Stack:** React 18, TypeScript, Tailwind CSS v4, better-sqlite3, CodeMirror 6, Lucide React, Electron webview, Web Audio API, OpenAI Whisper API

---

## Context for Implementers

**Working directory:** `/Users/nicknorris/Documents/claude-code-projects/claude-context-tool/.claude/worktrees/electron-port`

**All file paths are relative to `electron/src/`.**

**Established patterns:**
- DAOs: class with `constructor(private db: Database.Database)`, methods return typed models, use `.prepare().all()` / `.get()` / `.run()` — see `main/database/dao/NoteDAO.ts`
- IPC handlers: `export function registerXxxHandlers(db: Database.Database)`, use `ipcMain.handle(channel, handler)` — see `main/ipc/note-handlers.ts`
- Channel types in `shared/types.ts`: named type union, added to `IpcChannel`
- API facade in `renderer/lib/api.ts`: typed wrapper calling `invoke(channel, ...args)`
- Views in `renderer/views/XxxView.tsx`, components in `renderer/components/Xxx/`
- Tab routing in `renderer/layouts/ProjectLayout.tsx` switch/case
- Design tokens: `bg-neutral-900`, `border-neutral-800`, `text-neutral-400` secondary, `codefire-orange` accent, Lucide icons 14–16px

**DB tables already exist** (migrations 18 & 19 in `main/database/migrations/index.ts`):
- `generatedImages`: id, projectId, prompt, responseText, filePath, model, aspectRatio, imageSize, parentImageId, createdAt
- `recordings`: id (TEXT PK), projectId, title, audioPath, duration, transcript, status, errorMessage, createdAt

**Models already exist** in `shared/models.ts`:
- `GeneratedImage` interface
- `Recording` interface

**TabBar already lists** Images, Recordings, Browser tabs — they just route to "Coming soon".

---

## Task 1: ImageDAO — Database Access Layer

**Files:**
- Create: `main/database/dao/ImageDAO.ts`
- Modify: `main/database/dao/index.ts`

**Step 1: Create ImageDAO**

Create `electron/src/main/database/dao/ImageDAO.ts`:

```typescript
import Database from 'better-sqlite3'
import type { GeneratedImage } from '@shared/models'

export class ImageDAO {
  constructor(private db: Database.Database) {}

  list(projectId: string): GeneratedImage[] {
    return this.db
      .prepare('SELECT * FROM generatedImages WHERE projectId = ? ORDER BY createdAt DESC')
      .all(projectId) as GeneratedImage[]
  }

  getById(id: number): GeneratedImage | undefined {
    return this.db
      .prepare('SELECT * FROM generatedImages WHERE id = ?')
      .get(id) as GeneratedImage | undefined
  }

  create(data: {
    projectId: string
    prompt: string
    filePath: string
    model: string
    responseText?: string
    aspectRatio?: string
    imageSize?: string
    parentImageId?: number
  }): GeneratedImage {
    const now = new Date().toISOString()
    const result = this.db
      .prepare(
        `INSERT INTO generatedImages (projectId, prompt, responseText, filePath, model, aspectRatio, imageSize, parentImageId, createdAt)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        data.projectId,
        data.prompt,
        data.responseText ?? null,
        data.filePath,
        data.model,
        data.aspectRatio ?? '1:1',
        data.imageSize ?? '1K',
        data.parentImageId ?? null,
        now
      )
    return this.getById(Number(result.lastInsertRowid))!
  }

  delete(id: number): boolean {
    const result = this.db
      .prepare('DELETE FROM generatedImages WHERE id = ?')
      .run(id)
    return result.changes > 0
  }
}
```

**Step 2: Export from DAO index**

Add to `electron/src/main/database/dao/index.ts`:

```typescript
export { ImageDAO } from './ImageDAO'
```

**Step 3: Commit**

```bash
git add electron/src/main/database/dao/ImageDAO.ts electron/src/main/database/dao/index.ts
git commit -m "feat: add ImageDAO for generatedImages table"
```

---

## Task 2: Image IPC Handlers + Types + API

**Files:**
- Create: `main/ipc/image-handlers.ts`
- Modify: `shared/types.ts`
- Modify: `renderer/lib/api.ts`
- Modify: `main/ipc/index.ts`

**Step 1: Create image IPC handlers**

Create `electron/src/main/ipc/image-handlers.ts`:

```typescript
import { ipcMain } from 'electron'
import Database from 'better-sqlite3'
import { ImageDAO } from '../database/dao/ImageDAO'

export function registerImageHandlers(db: Database.Database) {
  const imageDAO = new ImageDAO(db)

  ipcMain.handle('images:list', (_e, projectId: string) =>
    imageDAO.list(projectId)
  )

  ipcMain.handle('images:get', (_e, id: number) =>
    imageDAO.getById(id)
  )

  ipcMain.handle(
    'images:create',
    (
      _e,
      data: {
        projectId: string
        prompt: string
        filePath: string
        model: string
        responseText?: string
        aspectRatio?: string
        imageSize?: string
        parentImageId?: number
      }
    ) => imageDAO.create(data)
  )

  ipcMain.handle('images:delete', (_e, id: number) =>
    imageDAO.delete(id)
  )
}
```

**Step 2: Add ImageChannel to types.ts**

In `electron/src/shared/types.ts`, add after the `ServiceChannel` type:

```typescript
export type ImageChannel =
  | 'images:list'
  | 'images:get'
  | 'images:create'
  | 'images:delete'
```

And add `| ImageChannel` to the `IpcChannel` union type.

**Step 3: Add images namespace to api.ts**

In `electron/src/renderer/lib/api.ts`, add the `GeneratedImage` import to the top import block:

```typescript
import type {
  Project,
  TaskItem,
  TaskNote,
  Note,
  Session,
  Client,
  GeneratedImage,
} from '@shared/models'
```

Then add the `images` namespace after the `services` namespace:

```typescript
  images: {
    list: (projectId: string) =>
      invoke('images:list', projectId) as Promise<GeneratedImage[]>,
    get: (id: number) =>
      invoke('images:get', id) as Promise<GeneratedImage | undefined>,
    create: (data: {
      projectId: string
      prompt: string
      filePath: string
      model: string
      responseText?: string
      aspectRatio?: string
      imageSize?: string
      parentImageId?: number
    }) => invoke('images:create', data) as Promise<GeneratedImage>,
    delete: (id: number) =>
      invoke('images:delete', id) as Promise<boolean>,
  },
```

**Step 4: Register in ipc/index.ts**

Add import at top of `electron/src/main/ipc/index.ts`:

```typescript
import { registerImageHandlers } from './image-handlers'
```

Add call in `registerAllHandlers` body, after `registerServiceHandlers()`:

```typescript
  registerImageHandlers(db)
```

**Step 5: Commit**

```bash
git add electron/src/main/ipc/image-handlers.ts electron/src/shared/types.ts electron/src/renderer/lib/api.ts electron/src/main/ipc/index.ts
git commit -m "feat: add image IPC handlers, channel types, and API facade"
```

---

## Task 3: Images View + Components

**Files:**
- Create: `renderer/views/ImagesView.tsx`
- Create: `renderer/components/Images/ImageHistoryList.tsx`
- Create: `renderer/components/Images/ImageViewer.tsx`
- Modify: `renderer/layouts/ProjectLayout.tsx`

**Step 1: Create ImageHistoryList component**

Create `electron/src/renderer/components/Images/ImageHistoryList.tsx`:

```typescript
import { Image, Trash2 } from 'lucide-react'
import type { GeneratedImage } from '@shared/models'

interface ImageHistoryListProps {
  images: GeneratedImage[]
  selectedId: number | null
  onSelect: (image: GeneratedImage) => void
  onDelete: (id: number) => void
}

export default function ImageHistoryList({
  images,
  selectedId,
  onSelect,
  onDelete,
}: ImageHistoryListProps) {
  if (images.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-neutral-500 gap-2">
        <Image size={24} />
        <p className="text-xs">No images yet</p>
        <p className="text-[10px] text-neutral-600">
          Generate images with AI tools
        </p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 py-2 border-b border-neutral-800">
        <p className="text-xs font-medium text-neutral-400 uppercase tracking-wider">
          Image History
        </p>
      </div>
      <div className="flex-1 overflow-y-auto">
        {images.map((img) => (
          <button
            key={img.id}
            type="button"
            onClick={() => onSelect(img)}
            className={`w-full text-left px-3 py-2 border-b border-neutral-800/50 hover:bg-neutral-800/60 transition-colors group ${
              selectedId === img.id ? 'bg-neutral-800/80' : ''
            }`}
          >
            <div className="flex items-start gap-2">
              <div className="w-10 h-10 rounded bg-neutral-800 overflow-hidden shrink-0 mt-0.5">
                <img
                  src={`file://${img.filePath}`}
                  alt=""
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    ;(e.target as HTMLImageElement).style.display = 'none'
                  }}
                />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-neutral-300 line-clamp-2">
                  {img.prompt}
                </p>
                <div className="flex items-center gap-2 mt-1">
                  <span className="text-[10px] text-neutral-600">
                    {img.model.split('/').pop()}
                  </span>
                  <span className="text-[10px] text-neutral-600">
                    {new Date(img.createdAt).toLocaleDateString()}
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onDelete(img.id)
                }}
                className="opacity-0 group-hover:opacity-100 text-neutral-600 hover:text-red-400 transition-all p-1"
              >
                <Trash2 size={12} />
              </button>
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
```

**Step 2: Create ImageViewer component**

Create `electron/src/renderer/components/Images/ImageViewer.tsx`:

```typescript
import { Image, Copy, ExternalLink, Maximize2 } from 'lucide-react'
import { useState } from 'react'
import type { GeneratedImage } from '@shared/models'

interface ImageViewerProps {
  image: GeneratedImage | null
}

export default function ImageViewer({ image }: ImageViewerProps) {
  const [isFullscreen, setIsFullscreen] = useState(false)

  if (!image) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-neutral-500 gap-2">
        <Image size={32} />
        <p className="text-sm">Select an image to view</p>
      </div>
    )
  }

  return (
    <>
      <div className="flex flex-col h-full">
        {/* Toolbar */}
        <div className="flex items-center gap-2 px-3 py-2 border-b border-neutral-800">
          <span className="text-[10px] font-mono text-neutral-500 bg-neutral-800 px-2 py-0.5 rounded">
            {image.aspectRatio ?? '1:1'}
          </span>
          <span className="text-[10px] font-mono text-neutral-500 bg-neutral-800 px-2 py-0.5 rounded">
            {image.model.split('/').pop()}
          </span>
          <div className="flex-1" />
          <button
            type="button"
            onClick={() => navigator.clipboard.writeText(image.filePath)}
            className="text-neutral-500 hover:text-neutral-300 transition-colors"
            title="Copy path"
          >
            <Copy size={14} />
          </button>
          <button
            type="button"
            onClick={() => window.open(`file://${image.filePath}`, '_blank')}
            className="text-neutral-500 hover:text-neutral-300 transition-colors"
            title="Open externally"
          >
            <ExternalLink size={14} />
          </button>
          <button
            type="button"
            onClick={() => setIsFullscreen(true)}
            className="text-neutral-500 hover:text-neutral-300 transition-colors"
            title="Fullscreen"
          >
            <Maximize2 size={14} />
          </button>
        </div>

        {/* Image display */}
        <div className="flex-1 overflow-auto p-4 flex items-center justify-center bg-neutral-950/50">
          <img
            src={`file://${image.filePath}`}
            alt={image.prompt}
            className="max-w-full max-h-full object-contain rounded-lg"
          />
        </div>

        {/* Prompt display */}
        <div className="px-3 py-2 border-t border-neutral-800">
          <p className="text-[10px] text-neutral-600 uppercase tracking-wider mb-1">Prompt</p>
          <p className="text-xs text-neutral-300">{image.prompt}</p>
          {image.responseText && (
            <>
              <p className="text-[10px] text-neutral-600 uppercase tracking-wider mt-2 mb-1">
                Response
              </p>
              <p className="text-xs text-neutral-400">{image.responseText}</p>
            </>
          )}
        </div>
      </div>

      {/* Fullscreen overlay */}
      {isFullscreen && (
        <div
          className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center cursor-pointer"
          onClick={() => setIsFullscreen(false)}
          onKeyDown={(e) => e.key === 'Escape' && setIsFullscreen(false)}
          role="button"
          tabIndex={0}
        >
          <img
            src={`file://${image.filePath}`}
            alt={image.prompt}
            className="max-w-[90vw] max-h-[90vh] object-contain"
          />
        </div>
      )}
    </>
  )
}
```

**Step 3: Create ImagesView**

Create `electron/src/renderer/views/ImagesView.tsx`:

```typescript
import { useState, useEffect } from 'react'
import { api } from '@renderer/lib/api'
import type { GeneratedImage } from '@shared/models'
import ImageHistoryList from '@renderer/components/Images/ImageHistoryList'
import ImageViewer from '@renderer/components/Images/ImageViewer'

interface ImagesViewProps {
  projectId: string
}

export default function ImagesView({ projectId }: ImagesViewProps) {
  const [images, setImages] = useState<GeneratedImage[]>([])
  const [selected, setSelected] = useState<GeneratedImage | null>(null)

  useEffect(() => {
    api.images.list(projectId).then((imgs) => {
      setImages(imgs)
      if (imgs.length > 0) setSelected(imgs[0])
    })
  }, [projectId])

  function handleDelete(id: number) {
    api.images.delete(id).then((ok) => {
      if (ok) {
        setImages((prev) => prev.filter((i) => i.id !== id))
        if (selected?.id === id) {
          setSelected(images.find((i) => i.id !== id) ?? null)
        }
      }
    })
  }

  return (
    <div className="flex h-full">
      {/* Left: History list */}
      <div className="w-64 border-r border-neutral-800 shrink-0">
        <ImageHistoryList
          images={images}
          selectedId={selected?.id ?? null}
          onSelect={setSelected}
          onDelete={handleDelete}
        />
      </div>

      {/* Right: Image viewer */}
      <div className="flex-1">
        <ImageViewer image={selected} />
      </div>
    </div>
  )
}
```

**Step 4: Wire into ProjectLayout**

In `electron/src/renderer/layouts/ProjectLayout.tsx`:

Add import:
```typescript
import ImagesView from '@renderer/views/ImagesView'
```

Add case in `renderActiveView` switch, after `case 'Git'`:
```typescript
      case 'Images':
        return <ImagesView projectId={pid} />
```

**Step 5: Verify build**

```bash
cd /Users/nicknorris/Documents/claude-code-projects/claude-context-tool/.claude/worktrees/electron-port/electron && npx tsc --noEmit
```

Expected: no errors.

**Step 6: Commit**

```bash
git add electron/src/renderer/views/ImagesView.tsx electron/src/renderer/components/Images/ electron/src/renderer/layouts/ProjectLayout.tsx
git commit -m "feat: add Images tab with history list and image viewer"
```

---

## Task 4: RecordingDAO — Database Access Layer

**Files:**
- Create: `main/database/dao/RecordingDAO.ts`
- Modify: `main/database/dao/index.ts`

**Step 1: Create RecordingDAO**

Create `electron/src/main/database/dao/RecordingDAO.ts`:

```typescript
import Database from 'better-sqlite3'
import { randomUUID } from 'node:crypto'
import type { Recording } from '@shared/models'

export class RecordingDAO {
  constructor(private db: Database.Database) {}

  list(projectId: string): Recording[] {
    return this.db
      .prepare('SELECT * FROM recordings WHERE projectId = ? ORDER BY createdAt DESC')
      .all(projectId) as Recording[]
  }

  getById(id: string): Recording | undefined {
    return this.db
      .prepare('SELECT * FROM recordings WHERE id = ?')
      .get(id) as Recording | undefined
  }

  create(data: {
    projectId: string
    title: string
    audioPath: string
  }): Recording {
    const id = randomUUID()
    const now = new Date().toISOString()
    this.db
      .prepare(
        `INSERT INTO recordings (id, projectId, title, audioPath, duration, status, createdAt)
         VALUES (?, ?, ?, ?, 0, 'recording', ?)`
      )
      .run(id, data.projectId, data.title, data.audioPath, now)
    return this.getById(id)!
  }

  update(
    id: string,
    data: {
      title?: string
      duration?: number
      transcript?: string
      status?: string
      errorMessage?: string
    }
  ): Recording | undefined {
    const existing = this.getById(id)
    if (!existing) return undefined

    this.db
      .prepare(
        `UPDATE recordings SET title = ?, duration = ?, transcript = ?, status = ?, errorMessage = ? WHERE id = ?`
      )
      .run(
        data.title ?? existing.title,
        data.duration ?? existing.duration,
        data.transcript ?? existing.transcript,
        data.status ?? existing.status,
        data.errorMessage ?? existing.errorMessage,
        id
      )
    return this.getById(id)
  }

  delete(id: string): boolean {
    const result = this.db
      .prepare('DELETE FROM recordings WHERE id = ?')
      .run(id)
    return result.changes > 0
  }
}
```

**Step 2: Export from DAO index**

Add to `electron/src/main/database/dao/index.ts`:

```typescript
export { RecordingDAO } from './RecordingDAO'
```

**Step 3: Commit**

```bash
git add electron/src/main/database/dao/RecordingDAO.ts electron/src/main/database/dao/index.ts
git commit -m "feat: add RecordingDAO for recordings table"
```

---

## Task 5: Recording IPC Handlers + Types + API

**Files:**
- Create: `main/ipc/recording-handlers.ts`
- Modify: `shared/types.ts`
- Modify: `renderer/lib/api.ts`
- Modify: `main/ipc/index.ts`

**Step 1: Create recording IPC handlers**

Create `electron/src/main/ipc/recording-handlers.ts`:

```typescript
import { ipcMain, app } from 'electron'
import Database from 'better-sqlite3'
import { RecordingDAO } from '../database/dao/RecordingDAO'
import * as path from 'node:path'
import * as fs from 'node:fs'

export function registerRecordingHandlers(db: Database.Database) {
  const recordingDAO = new RecordingDAO(db)

  ipcMain.handle('recordings:list', (_e, projectId: string) =>
    recordingDAO.list(projectId)
  )

  ipcMain.handle('recordings:get', (_e, id: string) =>
    recordingDAO.getById(id)
  )

  ipcMain.handle(
    'recordings:create',
    (_e, data: { projectId: string; title: string }) => {
      // Create recordings directory in app data
      const recordingsDir = path.join(app.getPath('userData'), 'recordings')
      if (!fs.existsSync(recordingsDir)) {
        fs.mkdirSync(recordingsDir, { recursive: true })
      }
      const audioPath = path.join(
        recordingsDir,
        `${Date.now()}-${data.title.replace(/[^a-zA-Z0-9]/g, '_')}.webm`
      )
      return recordingDAO.create({
        projectId: data.projectId,
        title: data.title,
        audioPath,
      })
    }
  )

  ipcMain.handle(
    'recordings:update',
    (
      _e,
      id: string,
      data: {
        title?: string
        duration?: number
        transcript?: string
        status?: string
        errorMessage?: string
      }
    ) => recordingDAO.update(id, data)
  )

  ipcMain.handle('recordings:delete', (_e, id: string) => {
    const recording = recordingDAO.getById(id)
    if (recording) {
      // Clean up audio file
      try {
        if (fs.existsSync(recording.audioPath)) {
          fs.unlinkSync(recording.audioPath)
        }
      } catch {
        // File may already be gone
      }
    }
    return recordingDAO.delete(id)
  })

  ipcMain.handle(
    'recordings:saveAudio',
    (_e, id: string, audioData: ArrayBuffer) => {
      const recording = recordingDAO.getById(id)
      if (!recording) return false
      fs.writeFileSync(recording.audioPath, Buffer.from(audioData))
      return true
    }
  )

  ipcMain.handle(
    'recordings:transcribe',
    async (_e, id: string, apiKey: string) => {
      const recording = recordingDAO.getById(id)
      if (!recording) throw new Error('Recording not found')
      if (!fs.existsSync(recording.audioPath)) {
        throw new Error('Audio file not found')
      }

      recordingDAO.update(id, { status: 'transcribing' })

      try {
        const audioBuffer = fs.readFileSync(recording.audioPath)
        const formData = new FormData()
        const blob = new Blob([audioBuffer], { type: 'audio/webm' })
        formData.append('file', blob, 'recording.webm')
        formData.append('model', 'whisper-1')
        formData.append('response_format', 'verbose_json')

        const response = await fetch(
          'https://api.openai.com/v1/audio/transcriptions',
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${apiKey}`,
            },
            body: formData,
          }
        )

        if (!response.ok) {
          const error = await response.text()
          throw new Error(`Whisper API error: ${response.status} ${error}`)
        }

        const result = (await response.json()) as { text: string; duration: number }
        return recordingDAO.update(id, {
          transcript: result.text,
          duration: result.duration,
          status: 'done',
        })
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error'
        recordingDAO.update(id, { status: 'error', errorMessage: message })
        throw err
      }
    }
  )
}
```

**Step 2: Add RecordingChannel to types.ts**

In `electron/src/shared/types.ts`, add after `ImageChannel`:

```typescript
export type RecordingChannel =
  | 'recordings:list'
  | 'recordings:get'
  | 'recordings:create'
  | 'recordings:update'
  | 'recordings:delete'
  | 'recordings:saveAudio'
  | 'recordings:transcribe'
```

Add `| RecordingChannel` to the `IpcChannel` union.

**Step 3: Add recordings namespace to api.ts**

In `electron/src/renderer/lib/api.ts`, add `Recording` to the model import:

```typescript
import type {
  Project,
  TaskItem,
  TaskNote,
  Note,
  Session,
  Client,
  GeneratedImage,
  Recording,
} from '@shared/models'
```

Then add the `recordings` namespace after `images`:

```typescript
  recordings: {
    list: (projectId: string) =>
      invoke('recordings:list', projectId) as Promise<Recording[]>,
    get: (id: string) =>
      invoke('recordings:get', id) as Promise<Recording | undefined>,
    create: (data: { projectId: string; title: string }) =>
      invoke('recordings:create', data) as Promise<Recording>,
    update: (
      id: string,
      data: {
        title?: string
        duration?: number
        transcript?: string
        status?: string
        errorMessage?: string
      }
    ) => invoke('recordings:update', id, data) as Promise<Recording | undefined>,
    delete: (id: string) =>
      invoke('recordings:delete', id) as Promise<boolean>,
    saveAudio: (id: string, audioData: ArrayBuffer) =>
      invoke('recordings:saveAudio', id, audioData) as Promise<boolean>,
    transcribe: (id: string, apiKey: string) =>
      invoke('recordings:transcribe', id, apiKey) as Promise<Recording>,
  },
```

**Step 4: Register in ipc/index.ts**

Add import:
```typescript
import { registerRecordingHandlers } from './recording-handlers'
```

Add call after `registerImageHandlers(db)`:
```typescript
  registerRecordingHandlers(db)
```

**Step 5: Commit**

```bash
git add electron/src/main/ipc/recording-handlers.ts electron/src/shared/types.ts electron/src/renderer/lib/api.ts electron/src/main/ipc/index.ts
git commit -m "feat: add recording IPC handlers with Whisper transcription support"
```

---

## Task 6: Recordings View + Components

**Files:**
- Create: `renderer/components/Recordings/RecordingBar.tsx`
- Create: `renderer/components/Recordings/RecordingsList.tsx`
- Create: `renderer/components/Recordings/RecordingDetail.tsx`
- Create: `renderer/hooks/useRecorder.ts`
- Create: `renderer/views/RecordingsView.tsx`
- Modify: `renderer/layouts/ProjectLayout.tsx`

**Step 1: Create useRecorder hook**

This hook wraps Web Audio API for recording. Create `electron/src/renderer/hooks/useRecorder.ts`:

```typescript
import { useState, useRef, useCallback } from 'react'

interface UseRecorderReturn {
  isRecording: boolean
  duration: number
  startRecording: () => Promise<void>
  stopRecording: () => Promise<Blob | null>
}

export function useRecorder(): UseRecorderReturn {
  const [isRecording, setIsRecording] = useState(false)
  const [duration, setDuration] = useState(0)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const chunksRef = useRef<Blob[]>([])
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const startTimeRef = useRef(0)

  const startRecording = useCallback(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    const mediaRecorder = new MediaRecorder(stream, {
      mimeType: 'audio/webm;codecs=opus',
    })

    chunksRef.current = []
    mediaRecorderRef.current = mediaRecorder

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data)
    }

    mediaRecorder.start(1000) // collect data every second
    startTimeRef.current = Date.now()
    setIsRecording(true)
    setDuration(0)

    timerRef.current = setInterval(() => {
      setDuration(Math.floor((Date.now() - startTimeRef.current) / 1000))
    }, 500)
  }, [])

  const stopRecording = useCallback(async (): Promise<Blob | null> => {
    return new Promise((resolve) => {
      const mediaRecorder = mediaRecorderRef.current
      if (!mediaRecorder || mediaRecorder.state === 'inactive') {
        resolve(null)
        return
      }

      mediaRecorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: 'audio/webm' })
        // Stop all tracks
        mediaRecorder.stream.getTracks().forEach((t) => t.stop())
        if (timerRef.current) clearInterval(timerRef.current)
        setIsRecording(false)
        resolve(blob)
      }

      mediaRecorder.stop()
    })
  }, [])

  return { isRecording, duration, startRecording, stopRecording }
}
```

**Step 2: Create RecordingBar component**

Create `electron/src/renderer/components/Recordings/RecordingBar.tsx`:

```typescript
import { Mic, Square, Loader2 } from 'lucide-react'
import { useState } from 'react'
import { useRecorder } from '@renderer/hooks/useRecorder'

interface RecordingBarProps {
  onRecordingComplete: (blob: Blob, title: string) => void
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

export default function RecordingBar({ onRecordingComplete }: RecordingBarProps) {
  const { isRecording, duration, startRecording, stopRecording } = useRecorder()
  const [title, setTitle] = useState('')
  const [starting, setStarting] = useState(false)

  async function handleStart() {
    setStarting(true)
    try {
      await startRecording()
    } catch (err) {
      console.error('Failed to start recording:', err)
    }
    setStarting(false)
  }

  async function handleStop() {
    const blob = await stopRecording()
    if (blob) {
      const recordingTitle = title.trim() || `Recording ${new Date().toLocaleString()}`
      onRecordingComplete(blob, recordingTitle)
      setTitle('')
    }
  }

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-b border-neutral-800 bg-neutral-900">
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Recording title..."
        disabled={isRecording}
        className="flex-1 bg-neutral-800 border border-neutral-700 rounded px-3 py-1.5 text-sm text-neutral-200 placeholder:text-neutral-600 focus:outline-none focus:border-codefire-orange/50 disabled:opacity-50"
      />

      {isRecording ? (
        <>
          <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
            <span className="text-sm font-mono text-red-400">
              {formatDuration(duration)}
            </span>
          </div>
          <button
            type="button"
            onClick={handleStop}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-red-500/20 text-red-400 hover:bg-red-500/30 rounded text-sm transition-colors"
          >
            <Square size={14} />
            Stop
          </button>
        </>
      ) : (
        <button
          type="button"
          onClick={handleStart}
          disabled={starting}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-codefire-orange/20 text-codefire-orange hover:bg-codefire-orange/30 rounded text-sm transition-colors disabled:opacity-50"
        >
          {starting ? <Loader2 size={14} className="animate-spin" /> : <Mic size={14} />}
          Record
        </button>
      )}
    </div>
  )
}
```

**Step 3: Create RecordingsList component**

Create `electron/src/renderer/components/Recordings/RecordingsList.tsx`:

```typescript
import { Mic, Trash2, Loader2, CheckCircle, AlertCircle, Clock } from 'lucide-react'
import type { Recording } from '@shared/models'

interface RecordingsListProps {
  recordings: Recording[]
  selectedId: string | null
  onSelect: (recording: Recording) => void
  onDelete: (id: string) => void
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.round(seconds % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}

function StatusIcon({ status }: { status: string }) {
  switch (status) {
    case 'recording':
      return <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
    case 'transcribing':
      return <Loader2 size={12} className="text-codefire-orange animate-spin" />
    case 'done':
      return <CheckCircle size={12} className="text-green-500" />
    case 'error':
      return <AlertCircle size={12} className="text-red-400" />
    default:
      return <Clock size={12} className="text-neutral-500" />
  }
}

export default function RecordingsList({
  recordings,
  selectedId,
  onSelect,
  onDelete,
}: RecordingsListProps) {
  if (recordings.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-neutral-500 gap-2">
        <Mic size={24} />
        <p className="text-xs">No recordings</p>
        <p className="text-[10px] text-neutral-600">
          Use the recorder above to get started
        </p>
      </div>
    )
  }

  return (
    <div className="flex-1 overflow-y-auto">
      {recordings.map((rec) => (
        <button
          key={rec.id}
          type="button"
          onClick={() => onSelect(rec)}
          className={`w-full text-left px-3 py-2.5 border-b border-neutral-800/50 hover:bg-neutral-800/60 transition-colors group ${
            selectedId === rec.id ? 'bg-neutral-800/80' : ''
          }`}
        >
          <div className="flex items-center gap-2">
            <StatusIcon status={rec.status} />
            <div className="flex-1 min-w-0">
              <p className="text-xs text-neutral-300 truncate">{rec.title}</p>
              <div className="flex items-center gap-2 mt-0.5">
                <span className="text-[10px] text-neutral-600">
                  {formatDuration(rec.duration)}
                </span>
                <span className="text-[10px] text-neutral-600">
                  {new Date(rec.createdAt).toLocaleDateString()}
                </span>
              </div>
            </div>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onDelete(rec.id)
              }}
              className="opacity-0 group-hover:opacity-100 text-neutral-600 hover:text-red-400 transition-all p-1"
            >
              <Trash2 size={12} />
            </button>
          </div>
        </button>
      ))}
    </div>
  )
}
```

**Step 4: Create RecordingDetail component**

Create `electron/src/renderer/components/Recordings/RecordingDetail.tsx`:

```typescript
import { Mic, Play, Pause, Key, Loader2 } from 'lucide-react'
import { useState, useRef } from 'react'
import type { Recording } from '@shared/models'

interface RecordingDetailProps {
  recording: Recording | null
  onTranscribe: (id: string) => void
  isTranscribing: boolean
}

export default function RecordingDetail({
  recording,
  onTranscribe,
  isTranscribing,
}: RecordingDetailProps) {
  const [isPlaying, setIsPlaying] = useState(false)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  if (!recording) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-neutral-500 gap-2">
        <Mic size={32} />
        <p className="text-sm">Select a recording</p>
      </div>
    )
  }

  function togglePlayback() {
    if (!audioRef.current) {
      audioRef.current = new Audio(`file://${recording!.audioPath}`)
      audioRef.current.onended = () => setIsPlaying(false)
    }

    if (isPlaying) {
      audioRef.current.pause()
      setIsPlaying(false)
    } else {
      audioRef.current.play()
      setIsPlaying(true)
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-neutral-800">
        <button
          type="button"
          onClick={togglePlayback}
          className="p-2 bg-codefire-orange/20 text-codefire-orange rounded-full hover:bg-codefire-orange/30 transition-colors"
        >
          {isPlaying ? <Pause size={16} /> : <Play size={16} />}
        </button>
        <div className="flex-1 min-w-0">
          <p className="text-sm text-neutral-200 font-medium truncate">
            {recording.title}
          </p>
          <p className="text-[10px] text-neutral-500">
            {Math.floor(recording.duration / 60)}m{' '}
            {Math.round(recording.duration % 60)}s —{' '}
            {new Date(recording.createdAt).toLocaleString()}
          </p>
        </div>

        {recording.status !== 'done' && recording.status !== 'transcribing' && (
          <button
            type="button"
            onClick={() => onTranscribe(recording.id)}
            disabled={isTranscribing}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 rounded text-xs transition-colors disabled:opacity-50"
          >
            {isTranscribing ? (
              <Loader2 size={12} className="animate-spin" />
            ) : (
              <Key size={12} />
            )}
            Transcribe
          </button>
        )}
      </div>

      {/* Transcript */}
      <div className="flex-1 overflow-y-auto p-4">
        {recording.status === 'transcribing' && (
          <div className="flex items-center justify-center gap-2 py-8 text-neutral-500">
            <Loader2 size={16} className="animate-spin" />
            <p className="text-sm">Transcribing with Whisper...</p>
          </div>
        )}

        {recording.status === 'error' && (
          <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3">
            <p className="text-xs text-red-400">{recording.errorMessage}</p>
          </div>
        )}

        {recording.transcript ? (
          <div className="space-y-3">
            <p className="text-[10px] text-neutral-600 uppercase tracking-wider">
              Transcript
            </p>
            <p className="text-sm text-neutral-300 leading-relaxed whitespace-pre-wrap">
              {recording.transcript}
            </p>
          </div>
        ) : (
          recording.status !== 'transcribing' &&
          recording.status !== 'error' && (
            <div className="flex flex-col items-center justify-center h-full text-neutral-500 gap-2">
              <p className="text-xs">No transcript yet</p>
              <p className="text-[10px] text-neutral-600">
                Click "Transcribe" to generate one with OpenAI Whisper
              </p>
            </div>
          )
        )}
      </div>
    </div>
  )
}
```

**Step 5: Create RecordingsView**

Create `electron/src/renderer/views/RecordingsView.tsx`:

```typescript
import { useState, useEffect } from 'react'
import { api } from '@renderer/lib/api'
import type { Recording } from '@shared/models'
import RecordingBar from '@renderer/components/Recordings/RecordingBar'
import RecordingsList from '@renderer/components/Recordings/RecordingsList'
import RecordingDetail from '@renderer/components/Recordings/RecordingDetail'

interface RecordingsViewProps {
  projectId: string
}

export default function RecordingsView({ projectId }: RecordingsViewProps) {
  const [recordings, setRecordings] = useState<Recording[]>([])
  const [selected, setSelected] = useState<Recording | null>(null)
  const [isTranscribing, setIsTranscribing] = useState(false)

  useEffect(() => {
    api.recordings.list(projectId).then((recs) => {
      setRecordings(recs)
      if (recs.length > 0) setSelected(recs[0])
    })
  }, [projectId])

  async function handleRecordingComplete(blob: Blob, title: string) {
    // Create recording record in DB (generates audioPath)
    const recording = await api.recordings.create({ projectId, title })

    // Save audio data to the generated path
    const arrayBuffer = await blob.arrayBuffer()
    await api.recordings.saveAudio(recording.id, arrayBuffer)

    // Update duration estimate from blob
    const updated = await api.recordings.update(recording.id, {
      status: 'recorded',
    })

    if (updated) {
      setRecordings((prev) => [updated, ...prev])
      setSelected(updated)
    }
  }

  async function handleTranscribe(id: string) {
    // Prompt for API key if not stored
    const apiKey = localStorage.getItem('openai_api_key')
    if (!apiKey) {
      const key = window.prompt('Enter your OpenAI API key for Whisper transcription:')
      if (!key) return
      localStorage.setItem('openai_api_key', key)
    }

    setIsTranscribing(true)
    try {
      const updated = await api.recordings.transcribe(
        id,
        localStorage.getItem('openai_api_key')!
      )
      if (updated) {
        setRecordings((prev) =>
          prev.map((r) => (r.id === id ? updated : r))
        )
        setSelected(updated)
      }
    } catch (err) {
      console.error('Transcription failed:', err)
      // Refresh to get error status
      const refreshed = await api.recordings.get(id)
      if (refreshed) {
        setRecordings((prev) =>
          prev.map((r) => (r.id === id ? refreshed : r))
        )
        setSelected(refreshed)
      }
    }
    setIsTranscribing(false)
  }

  function handleDelete(id: string) {
    api.recordings.delete(id).then((ok) => {
      if (ok) {
        setRecordings((prev) => prev.filter((r) => r.id !== id))
        if (selected?.id === id) {
          setSelected(recordings.find((r) => r.id !== id) ?? null)
        }
      }
    })
  }

  return (
    <div className="flex flex-col h-full">
      {/* Recording bar at top */}
      <RecordingBar onRecordingComplete={handleRecordingComplete} />

      {/* Split: list | detail */}
      <div className="flex flex-1 overflow-hidden">
        <div className="w-64 border-r border-neutral-800 flex flex-col shrink-0">
          <RecordingsList
            recordings={recordings}
            selectedId={selected?.id ?? null}
            onSelect={setSelected}
            onDelete={handleDelete}
          />
        </div>
        <div className="flex-1">
          <RecordingDetail
            recording={selected}
            onTranscribe={handleTranscribe}
            isTranscribing={isTranscribing}
          />
        </div>
      </div>
    </div>
  )
}
```

**Step 6: Wire into ProjectLayout**

In `electron/src/renderer/layouts/ProjectLayout.tsx`:

Add import:
```typescript
import RecordingsView from '@renderer/views/RecordingsView'
```

Add case in `renderActiveView` switch, after `case 'Images'`:
```typescript
      case 'Recordings':
        return <RecordingsView projectId={pid} />
```

**Step 7: Verify build**

```bash
cd /Users/nicknorris/Documents/claude-code-projects/claude-context-tool/.claude/worktrees/electron-port/electron && npx tsc --noEmit
```

**Step 8: Commit**

```bash
git add electron/src/renderer/views/RecordingsView.tsx electron/src/renderer/components/Recordings/ electron/src/renderer/hooks/useRecorder.ts electron/src/renderer/layouts/ProjectLayout.tsx
git commit -m "feat: add Recordings tab with Web Audio recording and Whisper transcription"
```

---

## Task 7: Browser Tab — Webview + URL Bar + Tab Strip

**Files:**
- Create: `renderer/components/Browser/BrowserTabStrip.tsx`
- Create: `renderer/components/Browser/BrowserToolbar.tsx`
- Create: `renderer/components/Browser/BrowserWebview.tsx`
- Create: `renderer/hooks/useBrowserTabs.ts`
- Create: `renderer/views/BrowserView.tsx`
- Modify: `renderer/layouts/ProjectLayout.tsx`

**Important Electron note:** The `<webview>` tag requires `webviewTag: true` in `BrowserWindow` webPreferences. Check `main/windows/WindowManager.ts` — if not already enabled, add it. Also ensure the `webview` tag is allowed in any CSP.

**Step 1: Create useBrowserTabs hook**

Create `electron/src/renderer/hooks/useBrowserTabs.ts`:

```typescript
import { useState, useCallback } from 'react'

export interface BrowserTab {
  id: string
  url: string
  title: string
  isLoading: boolean
}

let tabCounter = 0

export function useBrowserTabs() {
  const [tabs, setTabs] = useState<BrowserTab[]>([
    {
      id: `tab-${++tabCounter}`,
      url: 'about:blank',
      title: 'New Tab',
      isLoading: false,
    },
  ])
  const [activeTabId, setActiveTabId] = useState(tabs[0].id)

  const addTab = useCallback((url = 'about:blank') => {
    const id = `tab-${++tabCounter}`
    const tab: BrowserTab = { id, url, title: 'New Tab', isLoading: false }
    setTabs((prev) => [...prev, tab])
    setActiveTabId(id)
    return id
  }, [])

  const closeTab = useCallback(
    (id: string) => {
      setTabs((prev) => {
        const filtered = prev.filter((t) => t.id !== id)
        if (filtered.length === 0) {
          // Always keep at least one tab
          const newTab: BrowserTab = {
            id: `tab-${++tabCounter}`,
            url: 'about:blank',
            title: 'New Tab',
            isLoading: false,
          }
          setActiveTabId(newTab.id)
          return [newTab]
        }
        if (activeTabId === id) {
          setActiveTabId(filtered[filtered.length - 1].id)
        }
        return filtered
      })
    },
    [activeTabId]
  )

  const updateTab = useCallback(
    (id: string, updates: Partial<Omit<BrowserTab, 'id'>>) => {
      setTabs((prev) =>
        prev.map((t) => (t.id === id ? { ...t, ...updates } : t))
      )
    },
    []
  )

  const navigateTab = useCallback(
    (id: string, url: string) => {
      updateTab(id, { url, isLoading: true })
    },
    [updateTab]
  )

  const activeTab = tabs.find((t) => t.id === activeTabId) ?? tabs[0]

  return {
    tabs,
    activeTab,
    activeTabId,
    setActiveTabId,
    addTab,
    closeTab,
    updateTab,
    navigateTab,
  }
}
```

**Step 2: Create BrowserTabStrip**

Create `electron/src/renderer/components/Browser/BrowserTabStrip.tsx`:

```typescript
import { X, Plus, Loader2 } from 'lucide-react'
import type { BrowserTab } from '@renderer/hooks/useBrowserTabs'

interface BrowserTabStripProps {
  tabs: BrowserTab[]
  activeTabId: string
  onSelect: (id: string) => void
  onClose: (id: string) => void
  onAdd: () => void
}

export default function BrowserTabStrip({
  tabs,
  activeTabId,
  onSelect,
  onClose,
  onAdd,
}: BrowserTabStripProps) {
  return (
    <div className="flex items-center bg-neutral-900 border-b border-neutral-800 h-8">
      <div className="flex-1 flex items-center overflow-x-auto no-scrollbar">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => onSelect(tab.id)}
            className={`flex items-center gap-1.5 px-3 h-8 text-xs border-r border-neutral-800 shrink-0 max-w-[180px] group transition-colors ${
              tab.id === activeTabId
                ? 'bg-neutral-800 text-neutral-200'
                : 'text-neutral-500 hover:text-neutral-300 hover:bg-neutral-800/50'
            }`}
          >
            {tab.isLoading && (
              <Loader2 size={10} className="animate-spin shrink-0" />
            )}
            <span className="truncate">{tab.title}</span>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onClose(tab.id)
              }}
              className="opacity-0 group-hover:opacity-100 hover:text-red-400 transition-all ml-1 shrink-0"
            >
              <X size={10} />
            </button>
          </button>
        ))}
      </div>
      <button
        type="button"
        onClick={onAdd}
        className="px-2 h-8 text-neutral-500 hover:text-neutral-300 transition-colors shrink-0"
      >
        <Plus size={14} />
      </button>
    </div>
  )
}
```

**Step 3: Create BrowserToolbar**

Create `electron/src/renderer/components/Browser/BrowserToolbar.tsx`:

```typescript
import { ArrowLeft, ArrowRight, RotateCw, Home, Camera } from 'lucide-react'
import { useState, type KeyboardEvent } from 'react'

interface BrowserToolbarProps {
  url: string
  onNavigate: (url: string) => void
  onBack: () => void
  onForward: () => void
  onReload: () => void
  onScreenshot: () => void
  canGoBack: boolean
  canGoForward: boolean
}

export default function BrowserToolbar({
  url,
  onNavigate,
  onBack,
  onForward,
  onReload,
  onScreenshot,
  canGoBack,
  canGoForward,
}: BrowserToolbarProps) {
  const [inputUrl, setInputUrl] = useState(url)

  // Sync inputUrl when url prop changes (e.g. navigation within webview)
  if (url !== inputUrl && document.activeElement?.tagName !== 'INPUT') {
    setInputUrl(url)
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter') {
      let targetUrl = inputUrl.trim()
      if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
        targetUrl = `https://${targetUrl}`
      }
      setInputUrl(targetUrl)
      onNavigate(targetUrl)
    }
  }

  const btnClass =
    'p-1.5 text-neutral-500 hover:text-neutral-300 transition-colors disabled:opacity-30 disabled:cursor-not-allowed'

  return (
    <div className="flex items-center gap-1 px-2 py-1.5 border-b border-neutral-800 bg-neutral-900">
      <button
        type="button"
        onClick={onBack}
        disabled={!canGoBack}
        className={btnClass}
      >
        <ArrowLeft size={14} />
      </button>
      <button
        type="button"
        onClick={onForward}
        disabled={!canGoForward}
        className={btnClass}
      >
        <ArrowRight size={14} />
      </button>
      <button type="button" onClick={onReload} className={btnClass}>
        <RotateCw size={14} />
      </button>
      <button
        type="button"
        onClick={() => onNavigate('about:blank')}
        className={btnClass}
      >
        <Home size={14} />
      </button>

      <input
        type="text"
        value={inputUrl}
        onChange={(e) => setInputUrl(e.target.value)}
        onKeyDown={handleKeyDown}
        className="flex-1 bg-neutral-800 border border-neutral-700 rounded px-3 py-1 text-xs text-neutral-200 font-mono placeholder:text-neutral-600 focus:outline-none focus:border-codefire-orange/50"
        placeholder="Enter URL..."
      />

      <button type="button" onClick={onScreenshot} className={btnClass} title="Screenshot">
        <Camera size={14} />
      </button>
    </div>
  )
}
```

**Step 4: Create BrowserWebview**

Create `electron/src/renderer/components/Browser/BrowserWebview.tsx`:

```typescript
import { useEffect, useRef, useCallback, forwardRef, useImperativeHandle } from 'react'

interface BrowserWebviewProps {
  url: string
  isActive: boolean
  onTitleChange: (title: string) => void
  onUrlChange: (url: string) => void
  onLoadStart: () => void
  onLoadStop: () => void
  onConsoleMessage: (message: { level: string; message: string; line: number; source: string }) => void
}

export interface BrowserWebviewRef {
  goBack: () => void
  goForward: () => void
  reload: () => void
  canGoBack: () => boolean
  canGoForward: () => boolean
  getWebview: () => Electron.WebviewTag | null
  captureScreenshot: () => Promise<string | null>
}

const BrowserWebview = forwardRef<BrowserWebviewRef, BrowserWebviewProps>(
  function BrowserWebview(
    { url, isActive, onTitleChange, onUrlChange, onLoadStart, onLoadStop, onConsoleMessage },
    ref
  ) {
    const webviewRef = useRef<Electron.WebviewTag | null>(null)
    const lastUrlRef = useRef(url)

    useImperativeHandle(ref, () => ({
      goBack: () => webviewRef.current?.goBack(),
      goForward: () => webviewRef.current?.goForward(),
      reload: () => webviewRef.current?.reload(),
      canGoBack: () => webviewRef.current?.canGoBack() ?? false,
      canGoForward: () => webviewRef.current?.canGoForward() ?? false,
      getWebview: () => webviewRef.current,
      captureScreenshot: async () => {
        const wv = webviewRef.current
        if (!wv) return null
        try {
          const img = await (wv as any).capturePage()
          return img.toDataURL()
        } catch {
          return null
        }
      },
    }))

    const setupListeners = useCallback(
      (wv: Electron.WebviewTag) => {
        wv.addEventListener('page-title-updated', (e: any) => {
          onTitleChange(e.title)
        })
        wv.addEventListener('did-navigate', (e: any) => {
          onUrlChange(e.url)
        })
        wv.addEventListener('did-navigate-in-page', (e: any) => {
          if (e.isMainFrame) onUrlChange(e.url)
        })
        wv.addEventListener('did-start-loading', () => onLoadStart())
        wv.addEventListener('did-stop-loading', () => onLoadStop())
        wv.addEventListener('console-message', (e: any) => {
          onConsoleMessage({
            level: ['verbose', 'info', 'warning', 'error'][e.level] ?? 'info',
            message: e.message,
            line: e.line,
            source: e.sourceId,
          })
        })
      },
      [onTitleChange, onUrlChange, onLoadStart, onLoadStop, onConsoleMessage]
    )

    useEffect(() => {
      const wv = webviewRef.current
      if (wv) {
        wv.addEventListener('dom-ready', () => setupListeners(wv), { once: true })
      }
    }, [setupListeners])

    // Navigate when URL changes externally
    useEffect(() => {
      if (url !== lastUrlRef.current && webviewRef.current) {
        lastUrlRef.current = url
        webviewRef.current.loadURL(url)
      }
    }, [url])

    return (
      <webview
        ref={(el) => {
          webviewRef.current = el as Electron.WebviewTag | null
        }}
        src={url}
        style={{
          width: '100%',
          height: '100%',
          display: isActive ? 'flex' : 'none',
        }}
        // @ts-expect-error webview attributes
        allowpopups="true"
      />
    )
  }
)

export default BrowserWebview
```

**Step 5: Create BrowserView**

Create `electron/src/renderer/views/BrowserView.tsx`:

```typescript
import { useState, useRef, useCallback } from 'react'
import { useBrowserTabs } from '@renderer/hooks/useBrowserTabs'
import BrowserTabStrip from '@renderer/components/Browser/BrowserTabStrip'
import BrowserToolbar from '@renderer/components/Browser/BrowserToolbar'
import BrowserWebview, {
  type BrowserWebviewRef,
} from '@renderer/components/Browser/BrowserWebview'

interface BrowserViewProps {
  projectId: string
}

interface ConsoleEntry {
  level: string
  message: string
  line: number
  source: string
  timestamp: number
}

export default function BrowserView({ projectId: _projectId }: BrowserViewProps) {
  const {
    tabs,
    activeTab,
    activeTabId,
    setActiveTabId,
    addTab,
    closeTab,
    updateTab,
    navigateTab,
  } = useBrowserTabs()

  const webviewRefs = useRef<Record<string, BrowserWebviewRef | null>>({})
  const [canGoBack, setCanGoBack] = useState(false)
  const [canGoForward, setCanGoForward] = useState(false)
  const [consoleEntries, setConsoleEntries] = useState<ConsoleEntry[]>([])
  const [showDevTools, setShowDevTools] = useState(false)

  const activeRef = webviewRefs.current[activeTabId]

  const updateNavState = useCallback(() => {
    const ref = webviewRefs.current[activeTabId]
    setCanGoBack(ref?.canGoBack() ?? false)
    setCanGoForward(ref?.canGoForward() ?? false)
  }, [activeTabId])

  function handleNavigate(url: string) {
    navigateTab(activeTabId, url)
  }

  function handleScreenshot() {
    const ref = webviewRefs.current[activeTabId]
    if (ref) {
      ref.captureScreenshot().then((dataUrl) => {
        if (dataUrl) {
          // Open screenshot in new window
          const w = window.open('')
          if (w) {
            w.document.write(`<img src="${dataUrl}" style="max-width:100%">`)
          }
        }
      })
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Tab strip */}
      <BrowserTabStrip
        tabs={tabs}
        activeTabId={activeTabId}
        onSelect={setActiveTabId}
        onClose={closeTab}
        onAdd={() => addTab()}
      />

      {/* URL bar */}
      <BrowserToolbar
        url={activeTab.url}
        onNavigate={handleNavigate}
        onBack={() => activeRef?.goBack()}
        onForward={() => activeRef?.goForward()}
        onReload={() => activeRef?.reload()}
        onScreenshot={handleScreenshot}
        canGoBack={canGoBack}
        canGoForward={canGoForward}
      />

      {/* Webview area */}
      <div className="flex-1 relative bg-white">
        {tabs.map((tab) => (
          <BrowserWebview
            key={tab.id}
            ref={(el) => {
              webviewRefs.current[tab.id] = el
            }}
            url={tab.url}
            isActive={tab.id === activeTabId}
            onTitleChange={(title) => updateTab(tab.id, { title })}
            onUrlChange={(url) => {
              updateTab(tab.id, { url })
              if (tab.id === activeTabId) updateNavState()
            }}
            onLoadStart={() => updateTab(tab.id, { isLoading: true })}
            onLoadStop={() => {
              updateTab(tab.id, { isLoading: false })
              if (tab.id === activeTabId) updateNavState()
            }}
            onConsoleMessage={(msg) => {
              setConsoleEntries((prev) => [
                ...prev.slice(-499),
                { ...msg, timestamp: Date.now() },
              ])
            }}
          />
        ))}
      </div>

      {/* Console panel (toggle) */}
      {showDevTools && (
        <div className="h-48 border-t border-neutral-800 bg-neutral-900 flex flex-col">
          <div className="flex items-center justify-between px-3 py-1 border-b border-neutral-800">
            <span className="text-[10px] text-neutral-500 uppercase tracking-wider">
              Console
            </span>
            <button
              type="button"
              onClick={() => setConsoleEntries([])}
              className="text-[10px] text-neutral-600 hover:text-neutral-400"
            >
              Clear
            </button>
          </div>
          <div className="flex-1 overflow-y-auto p-2 font-mono text-[11px]">
            {consoleEntries.map((entry, i) => (
              <div
                key={i}
                className={`py-0.5 ${
                  entry.level === 'error'
                    ? 'text-red-400'
                    : entry.level === 'warning'
                      ? 'text-yellow-400'
                      : 'text-neutral-400'
                }`}
              >
                <span className="text-neutral-600 mr-2">
                  {new Date(entry.timestamp).toLocaleTimeString()}
                </span>
                {entry.message}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* DevTools toggle footer */}
      <div className="flex items-center px-3 py-1 border-t border-neutral-800 bg-neutral-900">
        <button
          type="button"
          onClick={() => setShowDevTools(!showDevTools)}
          className="text-[10px] text-neutral-600 hover:text-codefire-orange transition-colors"
        >
          {showDevTools ? 'Hide Console' : 'Show Console'}
        </button>
      </div>
    </div>
  )
}
```

**Step 6: Wire into ProjectLayout**

In `electron/src/renderer/layouts/ProjectLayout.tsx`:

Add import:
```typescript
import BrowserView from '@renderer/views/BrowserView'
```

Add case in `renderActiveView` switch, after `case 'Recordings'`:
```typescript
      case 'Browser':
        return <BrowserView projectId={pid} />
```

**Step 7: Enable webviewTag in BrowserWindow**

Check `electron/src/main/windows/WindowManager.ts` — in the `BrowserWindow` constructor options, ensure `webPreferences` includes:

```typescript
webviewTag: true,
```

If it's not there, add it alongside existing webPreferences.

**Step 8: Verify build**

```bash
cd /Users/nicknorris/Documents/claude-code-projects/claude-context-tool/.claude/worktrees/electron-port/electron && npx tsc --noEmit
```

**Step 9: Commit**

```bash
git add electron/src/renderer/views/BrowserView.tsx electron/src/renderer/components/Browser/ electron/src/renderer/hooks/useBrowserTabs.ts electron/src/renderer/layouts/ProjectLayout.tsx
git commit -m "feat: add Browser tab with webview, multi-tab, URL bar, and console panel"
```

---

## Task 8: Final Verification + Phase 2 Design Doc

**Step 1: Full TypeScript check**

```bash
cd /Users/nicknorris/Documents/claude-code-projects/claude-context-tool/.claude/worktrees/electron-port/electron && npx tsc --noEmit
```

Fix any errors found.

**Step 2: Verify all 12 tabs are routed**

Read `electron/src/renderer/layouts/ProjectLayout.tsx` and confirm the switch statement has cases for:
Dashboard, Sessions, Tasks, Notes, Files, Memory, Rules, Services, Git, Images, Recordings, Browser

**Step 3: Save Phase 2 design doc**

The Phase 2 design doc should already be at `docs/plans/2026-03-04-electron-phase2-tabs-design.md`. If not, create it with the design decisions from the brainstorming session.

**Step 4: Commit any remaining fixes**

```bash
git add -A
git commit -m "fix: Phase 2 final verification and cleanup"
```
