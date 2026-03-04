import { ipcMain } from 'electron'
import * as fs from 'fs'
import * as path from 'path'

export interface DetectedService {
  name: string
  configFile: string
  configPath: string
  dashboardUrl: string | null
  icon: string // lucide icon name
}

interface ServiceDefinition {
  name: string
  configFiles: string[]
  dashboardUrl: string | null
  icon: string
}

const KNOWN_SERVICES: ServiceDefinition[] = [
  {
    name: 'Firebase',
    configFiles: ['firebase.json', '.firebaserc'],
    dashboardUrl: 'https://console.firebase.google.com',
    icon: 'Flame',
  },
  {
    name: 'Supabase',
    configFiles: ['supabase/config.toml', 'supabase/.temp/project-ref'],
    dashboardUrl: 'https://supabase.com/dashboard',
    icon: 'Database',
  },
  {
    name: 'Vercel',
    configFiles: ['vercel.json', '.vercel/project.json'],
    dashboardUrl: 'https://vercel.com/dashboard',
    icon: 'Triangle',
  },
  {
    name: 'Netlify',
    configFiles: ['netlify.toml', '.netlify/state.json'],
    dashboardUrl: 'https://app.netlify.com',
    icon: 'Globe',
  },
  {
    name: 'AWS',
    configFiles: ['samconfig.toml', 'serverless.yml', 'serverless.yaml', 'cdk.json', '.aws/config'],
    dashboardUrl: 'https://console.aws.amazon.com',
    icon: 'Cloud',
  },
  {
    name: 'Docker',
    configFiles: ['Dockerfile', 'docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml'],
    dashboardUrl: null,
    icon: 'Container',
  },
  {
    name: 'PostgreSQL',
    configFiles: ['docker-compose.yml'], // Will check content for postgres service
    dashboardUrl: null,
    icon: 'Database',
  },
  {
    name: 'Redis',
    configFiles: ['redis.conf'],
    dashboardUrl: null,
    icon: 'Database',
  },
  {
    name: 'Prisma',
    configFiles: ['prisma/schema.prisma'],
    dashboardUrl: null,
    icon: 'Database',
  },
  {
    name: 'Drizzle',
    configFiles: ['drizzle.config.ts', 'drizzle.config.js'],
    dashboardUrl: null,
    icon: 'Database',
  },
]

/**
 * Register IPC handlers for service detection.
 */
export function registerServiceHandlers() {
  ipcMain.handle(
    'services:detect',
    (_event, projectPath: string): DetectedService[] => {
      if (!projectPath || typeof projectPath !== 'string') {
        throw new Error('projectPath is required and must be a string')
      }

      const detected: DetectedService[] = []
      const seen = new Set<string>()

      for (const service of KNOWN_SERVICES) {
        for (const configFile of service.configFiles) {
          const fullPath = path.join(projectPath, configFile)
          try {
            if (fs.existsSync(fullPath)) {
              // Special case: PostgreSQL detection via docker-compose
              if (service.name === 'PostgreSQL' && configFile.includes('docker-compose')) {
                try {
                  const content = fs.readFileSync(fullPath, 'utf-8')
                  if (!content.includes('postgres')) continue
                } catch {
                  continue
                }
              }

              if (!seen.has(service.name)) {
                seen.add(service.name)
                detected.push({
                  name: service.name,
                  configFile,
                  configPath: fullPath,
                  dashboardUrl: service.dashboardUrl,
                  icon: service.icon,
                })
              }
            }
          } catch {
            // Ignore permission errors etc.
          }
        }
      }

      // Also scan for .env files
      try {
        const entries = fs.readdirSync(projectPath)
        const envFiles = entries.filter(
          (e) => e === '.env' || e.startsWith('.env.')
        )
        if (envFiles.length > 0 && !seen.has('Environment Variables')) {
          detected.push({
            name: 'Environment Variables',
            configFile: envFiles.join(', '),
            configPath: path.join(projectPath, envFiles[0]),
            dashboardUrl: null,
            icon: 'KeyRound',
          })
        }
      } catch {
        // Ignore
      }

      return detected
    }
  )
}
