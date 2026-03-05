import { useState, useEffect, useCallback } from 'react'
import { Send, Loader2 } from 'lucide-react'
import { api } from '@renderer/lib/api'
import type { GeneratedImage } from '@shared/models'
import ImageHistoryList from '@renderer/components/Images/ImageHistoryList'
import ImageViewer from '@renderer/components/Images/ImageViewer'

interface ImagesViewProps {
  projectId: string
}

const API_KEY_STORAGE = 'codefire_openrouter_key'

export default function ImagesView({ projectId }: ImagesViewProps) {
  const [images, setImages] = useState<GeneratedImage[]>([])
  const [selected, setSelected] = useState<GeneratedImage | null>(null)
  const [prompt, setPrompt] = useState('')
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchImages = useCallback(async () => {
    const imgs = await api.images.list(projectId)
    setImages(imgs)
    if (imgs.length > 0 && !selected) setSelected(imgs[0])
  }, [projectId, selected])

  useEffect(() => {
    fetchImages()
  }, [fetchImages])

  function getApiKey(): string | null {
    let key = localStorage.getItem(API_KEY_STORAGE)
    if (!key) {
      key = window.prompt('Enter your OpenRouter API key:')
      if (key) localStorage.setItem(API_KEY_STORAGE, key)
    }
    return key
  }

  async function handleGenerate() {
    const trimmed = prompt.trim()
    if (!trimmed || generating) return

    const apiKey = getApiKey()
    if (!apiKey) return

    setGenerating(true)
    setError(null)

    try {
      const result = await api.images.generate({
        projectId,
        prompt: trimmed,
        apiKey,
      })

      if (result.error) {
        setError(result.error)
      } else if (result.image) {
        setImages((prev) => [result.image!, ...prev])
        setSelected(result.image)
        setPrompt('')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Generation failed')
    } finally {
      setGenerating(false)
    }
  }

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
    <div className="flex flex-col h-full">
      {/* Generation bar */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-neutral-800 bg-neutral-900 shrink-0">
        <input
          type="text"
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleGenerate()}
          placeholder="Describe an image to generate..."
          disabled={generating}
          className="flex-1 bg-neutral-800 border border-neutral-700 rounded px-3 py-1.5 text-xs text-neutral-200 placeholder:text-neutral-600 focus:outline-none focus:border-codefire-orange/50 disabled:opacity-50"
        />
        <button
          type="button"
          onClick={handleGenerate}
          disabled={!prompt.trim() || generating}
          className="p-1.5 rounded bg-codefire-orange/20 text-codefire-orange hover:bg-codefire-orange/30 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
        >
          {generating ? (
            <Loader2 size={14} className="animate-spin" />
          ) : (
            <Send size={14} />
          )}
        </button>
      </div>

      {/* Error banner */}
      {error && (
        <div className="px-3 py-1.5 bg-red-900/20 border-b border-red-800/30 text-xs text-red-400">
          {error}
        </div>
      )}

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden">
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
    </div>
  )
}
