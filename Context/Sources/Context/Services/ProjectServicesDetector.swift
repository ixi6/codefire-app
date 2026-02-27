import Foundation

// MARK: - Data Models

enum ServiceType: String, CaseIterable {
    case firebase = "Firebase"
    case supabase = "Supabase"
    case vercel = "Vercel"
    case netlify = "Netlify"
    case docker = "Docker"
    case railway = "Railway"
    case aws = "AWS Amplify"
}

struct DetectedService: Identifiable {
    let id = UUID()
    let type: ServiceType
    let projectId: String?
    let configPath: String
    let dashboardURL: URL?

    var icon: String {
        switch type {
        case .firebase: return "flame"
        case .supabase: return "server.rack"
        case .vercel: return "triangle"
        case .netlify: return "network"
        case .docker: return "shippingbox"
        case .railway: return "tram"
        case .aws: return "cloud"
        }
    }

    var displayName: String { type.rawValue }
}

struct EnvironmentFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let entries: [(key: String, value: String)]
}

// MARK: - Detector

enum ProjectServicesDetector {

    /// Scan a project directory for known service configuration files.
    static func scan(projectPath: String) -> [DetectedService] {
        let fm = FileManager.default
        var services: [DetectedService] = []

        // Firebase: firebase.json or .firebaserc
        let firebaseJson = (projectPath as NSString).appendingPathComponent("firebase.json")
        let firebaseRc = (projectPath as NSString).appendingPathComponent(".firebaserc")
        if fm.fileExists(atPath: firebaseJson) || fm.fileExists(atPath: firebaseRc) {
            var projectId: String?
            var dashboardURL: URL?
            if let data = fm.contents(atPath: firebaseRc),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [String: Any],
               let defaultId = projects["default"] as? String {
                projectId = defaultId
                dashboardURL = URL(string: "https://console.firebase.google.com/project/\(defaultId)")
            }
            let configPath = fm.fileExists(atPath: firebaseRc) ? firebaseRc : firebaseJson
            services.append(DetectedService(
                type: .firebase,
                projectId: projectId,
                configPath: configPath,
                dashboardURL: dashboardURL
            ))
        }

        // Supabase: supabase/config.toml
        let supabaseConfig = (projectPath as NSString).appendingPathComponent("supabase/config.toml")
        if fm.fileExists(atPath: supabaseConfig) {
            var ref: String?
            var dashboardURL: URL?
            // Try to extract the ref from .env files
            let envFiles = [".env", ".env.local", ".env.development", ".env.production"]
            let supabaseURLKeys = ["SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL", "VITE_SUPABASE_URL"]
            for envFile in envFiles {
                let envPath = (projectPath as NSString).appendingPathComponent(envFile)
                if let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
                    for line in contents.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                        let parts = trimmed.split(separator: "=", maxSplits: 1)
                        guard parts.count == 2 else { continue }
                        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let value = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if supabaseURLKeys.contains(key),
                           value.contains(".supabase.co") {
                            // Extract ref from https://{ref}.supabase.co
                            if let url = URL(string: value),
                               let host = url.host,
                               let dotIndex = host.firstIndex(of: ".") {
                                ref = String(host[host.startIndex..<dotIndex])
                                dashboardURL = URL(string: "https://supabase.com/dashboard/project/\(ref!)")
                            }
                        }
                        if ref != nil { break }
                    }
                }
                if ref != nil { break }
            }
            services.append(DetectedService(
                type: .supabase,
                projectId: ref,
                configPath: supabaseConfig,
                dashboardURL: dashboardURL
            ))
        }

        // Vercel: vercel.json or .vercel/project.json
        let vercelJson = (projectPath as NSString).appendingPathComponent("vercel.json")
        let vercelProjectJson = (projectPath as NSString).appendingPathComponent(".vercel/project.json")
        if fm.fileExists(atPath: vercelJson) || fm.fileExists(atPath: vercelProjectJson) {
            var projectId: String?
            var dashboardURL: URL? = URL(string: "https://vercel.com/dashboard")
            if let data = fm.contents(atPath: vercelProjectJson),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let orgId = json["orgId"] as? String
                let projName = json["projectId"] as? String
                if let org = orgId, let proj = projName {
                    projectId = proj
                    dashboardURL = URL(string: "https://vercel.com/\(org)/\(proj)")
                }
            }
            let configPath = fm.fileExists(atPath: vercelProjectJson) ? vercelProjectJson : vercelJson
            services.append(DetectedService(
                type: .vercel,
                projectId: projectId,
                configPath: configPath,
                dashboardURL: dashboardURL
            ))
        }

        // Netlify: netlify.toml
        let netlifyToml = (projectPath as NSString).appendingPathComponent("netlify.toml")
        if fm.fileExists(atPath: netlifyToml) {
            services.append(DetectedService(
                type: .netlify,
                projectId: nil,
                configPath: netlifyToml,
                dashboardURL: URL(string: "https://app.netlify.com")
            ))
        }

        // Docker: docker-compose.yml, docker-compose.yaml, or Dockerfile
        let dockerComposeYml = (projectPath as NSString).appendingPathComponent("docker-compose.yml")
        let dockerComposeYaml = (projectPath as NSString).appendingPathComponent("docker-compose.yaml")
        let dockerfile = (projectPath as NSString).appendingPathComponent("Dockerfile")
        if fm.fileExists(atPath: dockerComposeYml) || fm.fileExists(atPath: dockerComposeYaml) || fm.fileExists(atPath: dockerfile) {
            var configPath = dockerfile
            if fm.fileExists(atPath: dockerComposeYml) {
                configPath = dockerComposeYml
            } else if fm.fileExists(atPath: dockerComposeYaml) {
                configPath = dockerComposeYaml
            }
            services.append(DetectedService(
                type: .docker,
                projectId: nil,
                configPath: configPath,
                dashboardURL: nil
            ))
        }

        // Railway: railway.toml or railway.json
        let railwayToml = (projectPath as NSString).appendingPathComponent("railway.toml")
        let railwayJson = (projectPath as NSString).appendingPathComponent("railway.json")
        if fm.fileExists(atPath: railwayToml) || fm.fileExists(atPath: railwayJson) {
            let configPath = fm.fileExists(atPath: railwayToml) ? railwayToml : railwayJson
            services.append(DetectedService(
                type: .railway,
                projectId: nil,
                configPath: configPath,
                dashboardURL: URL(string: "https://railway.app/dashboard")
            ))
        }

        // AWS Amplify: amplify/ directory
        let amplifyDir = (projectPath as NSString).appendingPathComponent("amplify")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: amplifyDir, isDirectory: &isDir), isDir.boolValue {
            services.append(DetectedService(
                type: .aws,
                projectId: nil,
                configPath: amplifyDir,
                dashboardURL: URL(string: "https://console.aws.amazon.com/amplify")
            ))
        }

        return services
    }

    /// Scan for common environment files and parse their key=value entries.
    static func scanEnvironmentFiles(projectPath: String) -> [EnvironmentFile] {
        let fm = FileManager.default
        let envFileNames = [
            ".env",
            ".env.local",
            ".env.development",
            ".env.staging",
            ".env.production",
            ".env.example"
        ]

        var results: [EnvironmentFile] = []

        for name in envFileNames {
            let fullPath = (projectPath as NSString).appendingPathComponent(name)
            guard fm.fileExists(atPath: fullPath),
                  let contents = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            var entries: [(key: String, value: String)] = []
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                entries.append((key: key, value: value))
            }

            if !entries.isEmpty {
                results.append(EnvironmentFile(name: name, path: fullPath, entries: entries))
            }
        }

        return results
    }
}
