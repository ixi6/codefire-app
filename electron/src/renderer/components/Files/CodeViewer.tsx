import { useEffect, useRef, useState } from 'react'
import { Loader2, FileCode } from 'lucide-react'
import { api } from '@renderer/lib/api'
import { EditorView, lineNumbers, highlightActiveLine } from '@codemirror/view'
import { EditorState } from '@codemirror/state'
import { javascript } from '@codemirror/lang-javascript'
import { python } from '@codemirror/lang-python'
import { html } from '@codemirror/lang-html'
import { css } from '@codemirror/lang-css'
import { json } from '@codemirror/lang-json'
import { markdown } from '@codemirror/lang-markdown'
import { oneDark } from '@codemirror/theme-one-dark'

interface CodeViewerProps {
  filePath: string | null
}

function getExtension(filePath: string): string {
  const parts = filePath.split('.')
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ''
}

function getLanguageExtension(filePath: string) {
  const ext = getExtension(filePath)
  switch (ext) {
    case 'js':
    case 'jsx':
      return javascript({ jsx: true })
    case 'ts':
    case 'tsx':
      return javascript({ jsx: true, typescript: true })
    case 'py':
      return python()
    case 'html':
    case 'htm':
    case 'vue':
    case 'svelte':
      return html()
    case 'css':
    case 'scss':
    case 'less':
      return css()
    case 'json':
      return json()
    case 'md':
    case 'mdx':
    case 'markdown':
      return markdown()
    default:
      return null
  }
}

function getFileName(filePath: string): string {
  return filePath.split('/').pop() ?? filePath
}

export default function CodeViewer({ filePath }: CodeViewerProps) {
  const editorRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!filePath || !editorRef.current) return

    let cancelled = false
    setLoading(true)
    setError(null)

    api.files
      .read(filePath)
      .then((content) => {
        if (cancelled || !editorRef.current) return

        // Destroy previous editor
        if (viewRef.current) {
          viewRef.current.destroy()
          viewRef.current = null
        }

        const extensions = [
          lineNumbers(),
          highlightActiveLine(),
          EditorState.readOnly.of(true),
          EditorView.editable.of(false),
          oneDark,
          EditorView.theme({
            '&': { height: '100%', backgroundColor: 'transparent' },
            '.cm-scroller': { overflow: 'auto' },
            '.cm-gutters': { backgroundColor: 'transparent', borderRight: '1px solid #333' },
          }),
        ]

        const langExt = getLanguageExtension(filePath)
        if (langExt) {
          extensions.push(langExt)
        }

        const state = EditorState.create({
          doc: content,
          extensions,
        })

        viewRef.current = new EditorView({
          state,
          parent: editorRef.current,
        })

        setLoading(false)
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to read file')
          setLoading(false)
        }
      })

    return () => {
      cancelled = true
    }
  }, [filePath])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (viewRef.current) {
        viewRef.current.destroy()
        viewRef.current = null
      }
    }
  }, [])

  if (!filePath) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-neutral-600">
        <FileCode size={32} className="mb-2" />
        <p className="text-sm">Select a file to view</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      {/* File path header */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-neutral-800 shrink-0">
        <FileCode size={14} className="text-neutral-500" />
        <span className="text-xs text-neutral-400 truncate" title={filePath}>
          {getFileName(filePath)}
        </span>
        <span className="text-xs text-neutral-600 ml-auto truncate" title={filePath}>
          {filePath}
        </span>
      </div>

      {/* Editor area */}
      <div className="flex-1 overflow-hidden relative">
        {loading && (
          <div className="absolute inset-0 flex items-center justify-center bg-neutral-900/80 z-10">
            <Loader2 size={16} className="animate-spin text-neutral-500" />
          </div>
        )}

        {error && (
          <div className="absolute inset-0 flex items-center justify-center bg-neutral-900/80 z-10">
            <p className="text-sm text-error">{error}</p>
          </div>
        )}

        <div ref={editorRef} className="h-full" />
      </div>
    </div>
  )
}
