import MainLayout from '@renderer/layouts/MainLayout'
import ProjectLayout from '@renderer/layouts/ProjectLayout'

export default function App() {
  const params = new URLSearchParams(window.location.search)
  const projectId = params.get('projectId')

  if (projectId) {
    return <ProjectLayout projectId={projectId} />
  }

  return <MainLayout />
}
