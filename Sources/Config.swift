import Foundation

public struct AccountConfig: Codable, Identifiable, Equatable {
    public let id: String
    public let type: String // "codex" or "antigravity"
    public var label: String
    public var accessToken: String
    public var refreshToken: String
    public var accountId: String? // Codex only
    public var expiresAt: Date? // Expiration time for accessToken
    public var email: String? // Account email or username
    
    public init(id: String = UUID().uuidString, type: String, label: String, accessToken: String = "", refreshToken: String = "", accountId: String? = nil, expiresAt: Date? = nil, email: String? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.expiresAt = expiresAt
        self.email = email
    }
    
    public var displayName: String {
        if let email = email, !email.isEmpty {
            return email
        }
        return label
    }
}

public struct AppConfig: Codable {
    public var accounts: [AccountConfig]
    public var selectedAccountId: String?
    public var refreshInterval: Int? // in seconds
    public var menuBarStyle: String? // "bars", "percentage", "both"
    public var notificationsEnabled: Bool?
    public var notificationThreshold: Int? // remaining percentage, e.g. 15 for 15%
    
    public init(accounts: [AccountConfig] = [], selectedAccountId: String? = nil, refreshInterval: Int? = 60, menuBarStyle: String? = "bars", notificationsEnabled: Bool? = true, notificationThreshold: Int? = 15) {
        self.accounts = accounts
        self.selectedAccountId = selectedAccountId
        self.refreshInterval = refreshInterval
        self.menuBarStyle = menuBarStyle
        self.notificationsEnabled = notificationsEnabled
        self.notificationThreshold = notificationThreshold
    }
}

public class ConfigManager {
    public static let shared = ConfigManager()
    
    private let fileURL: URL
    
    private init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        fileURL = homeDirectory.appendingPathComponent(".limitbank.json")
    }
    
    public func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaultAppConfig = AppConfig(accounts: self.createDefaultAccounts())
            self.save(defaultAppConfig)
            return defaultAppConfig
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var config = try decoder.decode(AppConfig.self, from: data)
            
            // Ensure default 5 accounts exist if config is empty or incomplete
            if config.accounts.isEmpty {
                config.accounts = createDefaultAccounts()
            }
            return config
        } catch {
            AppLogger.log("Error loading config: \(error). Falling back to default.")
            return AppConfig(accounts: self.createDefaultAccounts())
        }
    }
    
    public func save(_ config: AppConfig) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.log("Error saving config: \(error)")
        }
    }
    
    private func createDefaultAccounts() -> [AccountConfig] {
        return [
            AccountConfig(type: "codex", label: "Codex Account 1"),
            AccountConfig(type: "codex", label: "Codex Account 2"),
            AccountConfig(type: "antigravity", label: "Antigravity Account 1"),
            AccountConfig(type: "antigravity", label: "Antigravity Account 2"),
            AccountConfig(type: "antigravity", label: "Antigravity Account 3")
        ]
    }
}

public class SystemCredentialDetector {
    public static func parseJWTClaim(_ token: String, claim: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        if claim == "email" {
            if let email = json["email"] as? String ?? json["email_address"] as? String ?? json["unique_name"] as? String ?? json["name"] as? String {
                return email
            }
            if let profile = json["https://api.openai.com/profile"] as? [String: Any],
               let email = profile["email"] as? String {
                return email
            }
        }
        
        return json[claim] as? String
    }

    public static func detectCodex() -> (accessToken: String, refreshToken: String, accountId: String?, email: String?)? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            homeDirectory.appendingPathComponent(".codex/auth.json"),
            homeDirectory.appendingPathComponent(".local/share/opencode/auth.json")
        ]
        
        for path in paths {
            guard FileManager.default.fileExists(atPath: path.path),
                  let data = try? Data(contentsOf: path) else { continue }
            
            // Try Codex format
            struct CodexAuthTokens: Codable {
                let access_token: String?
                let refresh_token: String?
                let id_token: String?
                let account_id: String?
            }
            struct CodexAuth: Codable {
                let tokens: CodexAuthTokens?
            }
            
            if let auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
               let tokens = auth.tokens {
                let email = tokens.id_token.flatMap { parseJWTClaim($0, claim: "email") }
                return (tokens.access_token ?? "", tokens.refresh_token ?? "", tokens.account_id, email)
            }
            
            // Try OpenCode format
            struct OpenCodeAuthOpenAI: Codable {
                let access: String?
                let refresh: String?
                let id_token: String?
                let idToken: String?
                let accountId: String?
            }
            struct OpenCodeAuth: Codable {
                let openai: OpenCodeAuthOpenAI?
            }
            
            if let auth = try? JSONDecoder().decode(OpenCodeAuth.self, from: data),
               let openai = auth.openai {
                let idToken = openai.id_token ?? openai.idToken ?? ""
                let email = idToken.isEmpty ? nil : parseJWTClaim(idToken, claim: "email")
                return (openai.access ?? "", openai.refresh ?? "", openai.accountId, email)
            }
        }
        
        return nil
    }
    
    public static func detectAntigravity() -> (accessToken: String, refreshToken: String, email: String?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gemini",
            kSecAttrAccount as String: "antigravity",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let rawString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        var jsonText = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "go-keyring-base64:"
        
        if jsonText.hasPrefix(prefix) {
            let base64Part = String(jsonText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let decodedData = Data(base64Encoded: base64Part),
               let decodedString = String(data: decodedData, encoding: .utf8) {
                jsonText = decodedString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        guard let jsonData = jsonText.data(using: .utf8) else { return nil }
        
        struct TokenObj: Codable {
            let access_token: String?
            let accessToken: String?
            let token: String?
            let refresh_token: String?
            let refreshToken: String?
            let id_token: String?
            let idToken: String?
        }
        
        struct KeychainEnvelope: Codable {
            let token: TokenObj?
            let access_token: String?
            let accessToken: String?
            let refresh_token: String?
            let refreshToken: String?
            let id_token: String?
            let idToken: String?
        }
        
        if let env = try? JSONDecoder().decode(KeychainEnvelope.self, from: jsonData) {
            let access = env.token?.access_token ?? env.token?.accessToken ?? env.token?.token ?? env.access_token ?? env.accessToken ?? ""
            let refresh = env.token?.refresh_token ?? env.token?.refreshToken ?? env.refresh_token ?? env.refreshToken ?? ""
            let idToken = env.token?.id_token ?? env.token?.idToken ?? env.id_token ?? env.idToken ?? ""
            let email = idToken.isEmpty ? nil : parseJWTClaim(idToken, claim: "email")
            return (access, refresh, email)
        }
        
        return nil
    }
    
    public static func launchCodexLogin() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        let backupURL = home.appendingPathComponent(".codex/auth.json.tmp")
        
        if FileManager.default.fileExists(atPath: authURL.path) {
            try? FileManager.default.removeItem(atPath: backupURL.path)
            try? FileManager.default.moveItem(at: authURL, to: backupURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "login"]
        
        var env = ProcessInfo.processInfo.environment
        let brewPath = "/opt/homebrew/bin:/usr/local/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = brewPath + ":" + currentPath
        } else {
            env["PATH"] = brewPath
        }
        process.environment = env
        
        try? process.run()
    }
}

public struct AppLogger {
    private static var logFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".limitbank.log")
    }
    
    public static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        print(message)
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
