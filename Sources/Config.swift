import AppKit
import Foundation

public struct AccountConfig: Codable, Identifiable, Equatable {
    public let id: String
    public let type: String // "codex" or "antigravity"
    public var label: String
    public var accessToken: String
    public var refreshToken: String
    public var idToken: String? // OAuth id token when available; used to restore app sessions
    public var accountId: String? // Codex only
    public var expiresAt: Date? // Expiration time for accessToken
    public var email: String? // Account email or username

    public init(id: String = UUID().uuidString, type: String, label: String, accessToken: String = "", refreshToken: String = "", idToken: String? = nil, accountId: String? = nil, expiresAt: Date? = nil, email: String? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
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

    public init(accounts: [AccountConfig] = [], selectedAccountId: String? = nil, refreshInterval: Int? = 60, menuBarStyle: String? = "bars") {
        self.accounts = accounts
        self.selectedAccountId = selectedAccountId
        self.refreshInterval = refreshInterval
        self.menuBarStyle = menuBarStyle
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
    private static let codexAppBundleIdentifier = "com.openai.codex"

    private static var codexHomeDirectory: URL {
        if let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredHome.isEmpty {
            return URL(fileURLWithPath: NSString(string: configuredHome).expandingTildeInPath, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private static var codexAuthURL: URL {
        codexHomeDirectory.appendingPathComponent("auth.json")
    }

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

    public static func detectCodex(includeOpenCodeFallback: Bool = true) -> (accessToken: String, refreshToken: String, idToken: String?, accountId: String?, email: String?)? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var paths = [codexAuthURL]
        if includeOpenCodeFallback {
            paths.append(homeDirectory.appendingPathComponent(".local/share/opencode/auth.json"))
        }

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
                let accessToken = tokens.access_token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let refreshToken = tokens.refresh_token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !accessToken.isEmpty, !refreshToken.isEmpty else { continue }
                let email = tokens.id_token.flatMap { parseJWTClaim($0, claim: "email") }
                return (accessToken, refreshToken, tokens.id_token, tokens.account_id, email)
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
                let accessToken = openai.access?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let refreshToken = openai.refresh?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !accessToken.isEmpty, !refreshToken.isEmpty else { continue }
                let idToken = openai.id_token ?? openai.idToken ?? ""
                let email = idToken.isEmpty ? nil : parseJWTClaim(idToken, claim: "email")
                return (accessToken, refreshToken, idToken.isEmpty ? nil : idToken, openai.accountId, email)
            }
        }

        return nil
    }

    public enum CodexAuthWriteError: LocalizedError {
        case unsupportedAccountType
        case missingTokens

        public var errorDescription: String? {
            switch self {
            case .unsupportedAccountType:
                return "Only Codex accounts can be activated into ~/.codex/auth.json."
            case .missingTokens:
                return "This account does not have saved Codex access and refresh tokens yet."
            }
        }
    }

    public enum CodexAppQuitError: LocalizedError {
        case timedOut([String])

        public var errorDescription: String? {
            switch self {
            case .timedOut(let appNames):
                return "ChatGPT is still running: \(appNames.joined(separator: ", ")). Quit ChatGPT manually, then activate the account again."
            }
        }
    }

    public enum CodexLoginError: LocalizedError {
        case executableNotFound
        case missingFileCredentials

        public var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Codex CLI was not found. Install the ChatGPT desktop app or Codex CLI, then try again."
            case .missingFileCredentials:
                return "ChatGPT sign-in finished, but Codex did not create a usable auth.json file."
            }
        }
    }

    public enum AntigravityAuthWriteError: LocalizedError {
        case unsupportedAccountType
        case missingTokens
        case keychainWriteFailed(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unsupportedAccountType:
                return "Only Antigravity accounts can be activated into macOS Keychain."
            case .missingTokens:
                return "This account does not have saved Antigravity access and refresh tokens yet."
            case .keychainWriteFailed(let status):
                return "Failed to write Antigravity credentials to Keychain (status \(status))."
            }
        }
    }

    public enum AntigravityAppQuitError: LocalizedError {
        case timedOut([String])

        public var errorDescription: String? {
            switch self {
            case .timedOut(let appNames):
                return "Antigravity is still running: \(appNames.joined(separator: ", ")). Quit Antigravity manually, then activate the account again."
            }
        }
    }

    @MainActor
    @discardableResult
    public static func quitRunningCodexApps(timeout: TimeInterval = 8) async throws -> Bool {
        let apps = runningCodexApplications()
        guard !apps.isEmpty else { return false }

        for app in apps where !app.isTerminated {
            _ = app.terminate()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningCodexApplications().isEmpty {
                return true
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let remainingNames = runningCodexApplications().map {
            $0.localizedName ?? $0.bundleIdentifier ?? "Codex"
        }
        throw CodexAppQuitError.timedOut(remainingNames)
    }

    @MainActor
    private static func runningCodexApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }

            if app.bundleIdentifier?.lowercased() == codexAppBundleIdentifier {
                return true
            }

            guard app.bundleIdentifier == nil else { return false }
            guard let name = app.localizedName?.lowercased() else {
                return false
            }

            return name == "codex" || name == "chatgpt"
        }
    }

    public static func openCodexApp() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var launchTargets = [["-b", codexAppBundleIdentifier]]
                let appPaths = [
                    "/Applications/ChatGPT.app",
                    "/Applications/Codex.app",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app").path
                ]
                launchTargets.append(contentsOf: appPaths
                    .filter {
                        Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier?.lowercased() == codexAppBundleIdentifier
                    }
                    .map { [$0] })
                launchTargets.append(["-a", "Codex"])

                for arguments in launchTargets {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = arguments

                    do {
                        try process.run()
                        process.waitUntilExit()
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: true)
                            return
                        }
                    } catch {
                        AppLogger.log("Failed to open ChatGPT/Codex using \(arguments.joined(separator: " ")): \(error.localizedDescription)")
                    }
                }

                continuation.resume(returning: false)
            }
        }
    }

    public static func openAntigravityApp() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Antigravity"]

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    AppLogger.log("Failed to open Antigravity app: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    @MainActor
    @discardableResult
    public static func quitRunningAntigravityApps(timeout: TimeInterval = 8) async throws -> Bool {
        let apps = runningAntigravityApplications()
        guard !apps.isEmpty else { return false }

        for app in apps where !app.isTerminated {
            _ = app.terminate()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningAntigravityApplications().isEmpty {
                return true
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let remainingNames = runningAntigravityApplications().map {
            $0.localizedName ?? $0.bundleIdentifier ?? "Antigravity"
        }
        throw AntigravityAppQuitError.timedOut(remainingNames)
    }

    @MainActor
    private static func runningAntigravityApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard !app.isTerminated else { return false }

            if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
               bundleIdentifier.contains("antigravity") {
                return true
            }

            guard let name = app.localizedName?.lowercased() else {
                return false
            }

            return name == "antigravity" || name.hasPrefix("antigravity ")
        }
    }

    public static func writeCodexAuthFile(for account: AccountConfig) throws {
        guard account.type == "codex" else {
            throw CodexAuthWriteError.unsupportedAccountType
        }

        let accessToken = account.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = account.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw CodexAuthWriteError.missingTokens
        }

        let codexDir = codexHomeDirectory
        let authURL = codexAuthURL

        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: authURL.path),
           let data = try? Data(contentsOf: authURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        var tokens = root["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = refreshToken

        if let idToken = account.idToken?.trimmingCharacters(in: .whitespacesAndNewlines), !idToken.isEmpty {
            tokens["id_token"] = idToken
        } else {
            tokens.removeValue(forKey: "id_token")
        }

        if let accountId = account.accountId?.trimmingCharacters(in: .whitespacesAndNewlines), !accountId.isEmpty {
            tokens["account_id"] = accountId
        } else {
            tokens.removeValue(forKey: "account_id")
        }

        root["tokens"] = tokens
        root["auth_mode"] = "chatgpt"
        root["OPENAI_API_KEY"] = NSNull()
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: authURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
    }

    public static func writeAntigravityKeychain(for account: AccountConfig) throws {
        guard account.type == "antigravity" else {
            throw AntigravityAuthWriteError.unsupportedAccountType
        }

        let accessToken = account.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = account.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw AntigravityAuthWriteError.missingTokens
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gemini",
            kSecAttrAccount as String: "antigravity",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var existingDataRef: AnyObject?
        let existingStatus = SecItemCopyMatching(query as CFDictionary, &existingDataRef)
        var useGoKeyringPrefix = true
        var root: [String: Any] = [:]

        if existingStatus == errSecSuccess,
           let existingData = existingDataRef as? Data,
           let existingRaw = String(data: existingData, encoding: .utf8) {
            let prefix = "go-keyring-base64:"
            var jsonText = existingRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            useGoKeyringPrefix = jsonText.hasPrefix(prefix)

            if useGoKeyringPrefix {
                let base64Part = String(jsonText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let decodedData = Data(base64Encoded: base64Part),
                   let decodedString = String(data: decodedData, encoding: .utf8) {
                    jsonText = decodedString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if let jsonData = jsonText.data(using: .utf8),
               let existingRoot = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                root = existingRoot
            }
        }

        let expiryString = account.expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        let idToken = account.idToken?.trimmingCharacters(in: .whitespacesAndNewlines)

        func updateTokenDictionary(_ dictionary: inout [String: Any]) {
            dictionary["access_token"] = accessToken
            dictionary["refresh_token"] = refreshToken
            dictionary["token_type"] = dictionary["token_type"] ?? "Bearer"

            if let expiryString = expiryString {
                dictionary["expiry"] = expiryString
            }

            if let idToken = idToken, !idToken.isEmpty {
                dictionary["id_token"] = idToken
            } else {
                dictionary.removeValue(forKey: "id_token")
            }
        }

        if var nestedToken = root["token"] as? [String: Any] {
            updateTokenDictionary(&nestedToken)
            root["token"] = nestedToken
        } else {
            updateTokenDictionary(&root)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let rawString: String
        if useGoKeyringPrefix {
            rawString = "go-keyring-base64:" + jsonData.base64EncodedString()
        } else {
            rawString = String(data: jsonData, encoding: .utf8) ?? "{}"
        }
        let rawData = rawString.data(using: .utf8) ?? Data()

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gemini",
            kSecAttrAccount as String: "antigravity"
        ]

        if existingStatus == errSecSuccess {
            let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: rawData] as CFDictionary)
            guard status == errSecSuccess else {
                throw AntigravityAuthWriteError.keychainWriteFailed(status)
            }
        } else {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = rawData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw AntigravityAuthWriteError.keychainWriteFailed(status)
            }
        }
    }

    public static func detectAntigravity() -> (accessToken: String, refreshToken: String, idToken: String?, email: String?)? {
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
            return (access, refresh, idToken.isEmpty ? nil : idToken, email)
        }

        return nil
    }

    private static func codexExecutableURL() -> URL? {
        var candidates: [URL] = []
        var searchPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        searchPaths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])

        for directory in searchPaths {
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("codex"))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex")
        ])

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func codexLoginProcess() throws -> Process {
        guard let executableURL = codexExecutableURL() else {
            throw CodexLoginError.executableNotFound
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["login", "-c", "cli_auth_credentials_store=\"file\""]

        var env = ProcessInfo.processInfo.environment
        let brewPath = "/opt/homebrew/bin:/usr/local/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = brewPath + ":" + currentPath
        } else {
            env["PATH"] = brewPath
        }
        process.environment = env
        return process
    }

    private static func prepareCodexLoginFileSlot() throws -> Data? {
        guard FileManager.default.fileExists(atPath: codexAuthURL.path) else { return nil }
        let previousAuth = try Data(contentsOf: codexAuthURL)
        try FileManager.default.removeItem(at: codexAuthURL)
        return previousAuth
    }

    private static func restoreCodexLoginFile(_ previousAuth: Data?) {
        do {
            if FileManager.default.fileExists(atPath: codexAuthURL.path) {
                try FileManager.default.removeItem(at: codexAuthURL)
            }
            guard let previousAuth else { return }
            try FileManager.default.createDirectory(at: codexHomeDirectory, withIntermediateDirectories: true)
            try previousAuth.write(to: codexAuthURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: codexAuthURL.path)
        } catch {
            AppLogger.log("Failed to restore the previous Codex login after an unsuccessful sign-in: \(error.localizedDescription)")
        }
    }

    public static func loginCodexAndWait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var previousAuth: Data?

                do {
                    previousAuth = try prepareCodexLoginFileSlot()
                    let process = try codexLoginProcess()
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        if detectCodex(includeOpenCodeFallback: false) != nil {
                            continuation.resume()
                        } else {
                            restoreCodexLoginFile(previousAuth)
                            continuation.resume(throwing: CodexLoginError.missingFileCredentials)
                        }
                    } else {
                        restoreCodexLoginFile(previousAuth)
                        continuation.resume(throwing: NSError(
                            domain: "SystemCredentialDetector",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "Codex CLI login exited with status \(process.terminationStatus)."]
                        ))
                    }
                } catch {
                    restoreCodexLoginFile(previousAuth)
                    continuation.resume(throwing: error)
                }
            }
        }
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
