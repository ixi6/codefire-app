import type { ReactNode } from 'react'

interface TabButtonProps {
  label: string
  icon: ReactNode
  isActive: boolean
  onClick: () => void
}

export default function TabButton({ label, icon, isActive, onClick }: TabButtonProps) {
  return (
    <button
      className={`
        flex items-center gap-1.5 px-2 py-1.5 whitespace-nowrap
        border-b-2 transition-colors duration-100
        ${
          isActive
            ? 'border-codefire-orange text-codefire-orange'
            : 'border-transparent text-neutral-500 hover:text-neutral-300'
        }
      `}
      onClick={onClick}
    >
      <span className="[&>svg]:w-4 [&>svg]:h-4">{icon}</span>
      <span className="text-sm leading-none">{label}</span>
    </button>
  )
}
