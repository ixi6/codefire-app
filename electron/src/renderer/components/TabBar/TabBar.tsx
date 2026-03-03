import {
  LayoutDashboard,
  Clock,
  CheckSquare,
  FileText,
  FolderOpen,
  Brain,
  ScrollText,
  Cloud,
  GitBranch,
  Image,
  Mic,
  Globe,
} from 'lucide-react'
import TabButton from './TabButton'

interface TabBarProps {
  activeTab: string
  onTabChange: (tab: string) => void
}

const tabs = [
  { id: 'Dashboard', icon: LayoutDashboard },
  { id: 'Sessions', icon: Clock },
  { id: 'Tasks', icon: CheckSquare },
  { id: 'Notes', icon: FileText },
  { id: 'Files', icon: FolderOpen },
  { id: 'Memory', icon: Brain },
  { id: 'Rules', icon: ScrollText },
  { id: 'Services', icon: Cloud },
  { id: 'Git', icon: GitBranch },
  { id: 'Images', icon: Image },
  { id: 'Recordings', icon: Mic },
  { id: 'Browser', icon: Globe },
] as const

export default function TabBar({ activeTab, onTabChange }: TabBarProps) {
  return (
    <div className="flex items-center overflow-x-auto scrollbar-none bg-neutral-900 border-b border-neutral-800 shrink-0">
      {tabs.map((tab) => (
        <TabButton
          key={tab.id}
          label={tab.id}
          icon={<tab.icon size={16} />}
          isActive={activeTab === tab.id}
          onClick={() => onTabChange(tab.id)}
        />
      ))}
    </div>
  )
}
