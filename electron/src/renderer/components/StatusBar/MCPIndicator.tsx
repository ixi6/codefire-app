import { Radio } from 'lucide-react'

interface MCPIndicatorProps {
  status: 'connected' | 'disconnected' | 'error'
  sessionCount?: number
}

const statusConfig = {
  connected: {
    dotClass: 'bg-success',
    label: 'Connected',
    tooltip: 'MCP server is connected to Claude Code',
  },
  disconnected: {
    dotClass: 'bg-neutral-600',
    label: 'Disconnected',
    tooltip: 'MCP server is not connected',
  },
  error: {
    dotClass: 'bg-error',
    label: 'Error',
    tooltip: 'MCP server connection error',
  },
} as const

export default function MCPIndicator({
  status,
  sessionCount,
}: MCPIndicatorProps) {
  const config = statusConfig[status]

  const tooltipText =
    sessionCount !== undefined && sessionCount > 0
      ? `${config.tooltip} (${sessionCount} active session${sessionCount !== 1 ? 's' : ''})`
      : config.tooltip

  return (
    <div
      className="flex items-center gap-1.5 cursor-default"
      title={tooltipText}
    >
      <span
        className={`inline-block w-2 h-2 rounded-full flex-shrink-0 ${config.dotClass}`}
      />
      <Radio className="w-3 h-3 text-neutral-500 flex-shrink-0" />
      <span className="text-tiny text-neutral-500">
        MCP
        {sessionCount !== undefined && sessionCount > 0 && (
          <span className="text-neutral-600 ml-0.5">({sessionCount})</span>
        )}
      </span>
    </div>
  )
}
