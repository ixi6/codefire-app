import { Folder, FolderOpen, FileCode, FileText } from 'lucide-react'

interface FileTreeRowProps {
  name: string
  isDirectory: boolean
  isExpanded?: boolean
  isSelected?: boolean
  depth: number
  onClick: () => void
}

/** File extensions that get the code icon */
const CODE_EXTENSIONS = new Set([
  'ts', 'tsx', 'js', 'jsx', 'py', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h',
  'cs', 'php', 'swift', 'kt', 'scala', 'sh', 'bash', 'zsh', 'vue', 'svelte',
])

function getExtension(name: string): string {
  const parts = name.split('.')
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ''
}

export default function FileTreeRow({
  name,
  isDirectory,
  isExpanded,
  isSelected,
  depth,
  onClick,
}: FileTreeRowProps) {
  const ext = getExtension(name)
  const isCode = CODE_EXTENSIONS.has(ext)

  const Icon = isDirectory
    ? isExpanded
      ? FolderOpen
      : Folder
    : isCode
      ? FileCode
      : FileText

  const iconColor = isDirectory
    ? 'text-codefire-orange'
    : isCode
      ? 'text-blue-400'
      : 'text-neutral-500'

  return (
    <button
      className={`w-full flex items-center gap-1.5 py-1 px-2 text-left text-sm
        hover:bg-neutral-800/60 transition-colors truncate
        ${isSelected ? 'bg-neutral-800 text-neutral-100' : 'text-neutral-400'}`}
      style={{ paddingLeft: `${depth * 16 + 8}px` }}
      onClick={onClick}
    >
      <Icon size={14} className={`shrink-0 ${iconColor}`} />
      <span className="truncate">{name}</span>
    </button>
  )
}
