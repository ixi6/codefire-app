import { ipcMain, shell, net } from 'electron'
import { app } from 'electron'

const GITHUB_REPO = 'websitebutlers/codefire-app'

function compareVersions(a: string, b: string): number {
  const pa = a.replace(/^v/, '').split('.').map(Number)
  const pb = b.replace(/^v/, '').split('.').map(Number)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const va = pa[i] || 0
    const vb = pb[i] || 0
    if (va > vb) return 1
    if (va < vb) return -1
  }
  return 0
}

async function fetchJSON(url: string): Promise<any> {
  return new Promise((resolve, reject) => {
    const request = net.request(url)
    request.setHeader('User-Agent', 'CodeFire-Electron')
    request.setHeader('Accept', 'application/vnd.github+json')
    let body = ''
    request.on('response', (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        const location = response.headers['location']
        if (location) {
          const redirectUrl = Array.isArray(location) ? location[0] : location
          fetchJSON(redirectUrl).then(resolve).catch(reject)
          return
        }
      }
      response.on('data', (chunk) => { body += chunk.toString() })
      response.on('end', () => {
        try { resolve(JSON.parse(body)) }
        catch { reject(new Error('Invalid JSON')) }
      })
      response.on('error', reject)
    })
    request.on('error', reject)
    request.end()
  })
}

export function registerUpdateHandlers() {
  ipcMain.handle('update:check', async () => {
    const currentVersion = app.getVersion()
    try {
      const release = await fetchJSON(
        `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`
      )
      const latestVersion = (release.tag_name || '').replace(/^v/, '')
      const available = compareVersions(latestVersion, currentVersion) > 0

      // Find the right asset for this platform
      const platform = process.platform
      const assets = release.assets || []
      let downloadUrl: string | null = null
      for (const asset of assets) {
        const name = (asset.name || '').toLowerCase()
        if (platform === 'win32' && name.endsWith('.exe')) {
          downloadUrl = asset.browser_download_url; break
        }
        if (platform === 'linux' && name.endsWith('.appimage')) {
          downloadUrl = asset.browser_download_url; break
        }
        if (platform === 'darwin' && name.endsWith('.dmg')) {
          downloadUrl = asset.browser_download_url; break
        }
      }

      return {
        available,
        currentVersion,
        latestVersion,
        downloadUrl,
        releaseNotes: release.body || null,
      }
    } catch {
      return { available: false, currentVersion, latestVersion: null, downloadUrl: null, releaseNotes: null }
    }
  })

  ipcMain.handle('update:download', async (_e, url: string) => {
    try {
      await shell.openExternal(url)
      return { success: true }
    } catch {
      return { success: false }
    }
  })
}
