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
