import Foundation
import Combine
import SwiftUI

@MainActor
public class QuotaMonitor: ObservableObject {
    public static let shared = QuotaMonitor()

    @Published public var config: AppConfig
    @Published public var statuses: [String: QuotaStatus] = [:]
    @Published public var isRefreshing = false
    @Published public var lastRefreshedAt: Date? = nil

    private var timer: AnyCancellable?
    private var refreshGeneration = 0

    public var onIconUpdate: (() -> Void)?

    private init() {
        self.config = ConfigManager.shared.load()
        // If no account is selected, select the first one by default
        if self.config.selectedAccountId == nil, let first = self.config.accounts.first {
            self.config.selectedAccountId = first.id
        }

        self.startPolling()

        // Trigger initial fetch asynchronously
        Task {
            await self.refreshAll()
        }
    }

    public func startPolling() {
        let interval = Double(config.refreshInterval ?? 60)
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.refreshAll()
                }
            }
    }

    public func stopPolling() {
        timer?.cancel()
    }

    public func selectAccount(id: String) {
        config.selectedAccountId = id
        ConfigManager.shared.save(config)
        onIconUpdate?()
    }

    public func getSelectedAccount() -> AccountConfig? {
        if let id = config.selectedAccountId {
            return config.accounts.first(where: { $0.id == id })
        }
        return config.accounts.first
    }

    public var selectedAccountIndex: Int {
        let selectedId = config.selectedAccountId ?? ""
        return config.accounts.firstIndex(where: { $0.id == selectedId }) ?? 0
    }

    public func getSelectedQuotaPercentages() -> (hours: Double?, weekly: Double?) {
        guard let account = getSelectedAccount(),
              let status = statuses[account.id] else {
            return (nil, nil)
        }

        if status.error != nil {
            return (nil, nil)
        }

        if account.type == "codex" {
            let hoursRemaining: Double?
            if let used = status.hoursUsedPercent {
                hoursRemaining = max(0.0, 100.0 - used)
            } else {
                hoursRemaining = nil
            }

            let weeklyRemaining: Double?
            if let used = status.weeklyUsedPercent {
                weeklyRemaining = max(0.0, 100.0 - used)
            } else {
                weeklyRemaining = nil
            }
            return (hoursRemaining, weeklyRemaining)
        } else {
            // Antigravity: return worst case between Gemini and 3P (Claude/GPT)
            var hoursRemaining: Double? = nil
            let geminiH = status.geminiHoursUsedPercent.map { max(0.0, 100.0 - $0) }
            let thirdPartyH = status.thirdPartyHoursUsedPercent.map { max(0.0, 100.0 - $0) }

            if let g = geminiH, let t = thirdPartyH {
                hoursRemaining = min(g, t)
            } else {
                hoursRemaining = geminiH ?? thirdPartyH
            }

            var weeklyRemaining: Double? = nil
            let geminiW = status.geminiWeeklyUsedPercent.map { max(0.0, 100.0 - $0) }
            let thirdPartyW = status.thirdPartyWeeklyUsedPercent.map { max(0.0, 100.0 - $0) }

            if let g = geminiW, let t = thirdPartyW {
                weeklyRemaining = min(g, t)
            } else {
                weeklyRemaining = geminiW ?? thirdPartyW
            }

            return (hoursRemaining, weeklyRemaining)
        }
    }

    private func invalidateInFlightRefreshes() {
        refreshGeneration &+= 1
    }

    private func ensureRefreshIsCurrent(_ generation: Int) throws {
        guard generation == refreshGeneration else {
            throw NSError(domain: "QuotaMonitor", code: -10, userInfo: [NSLocalizedDescriptionKey: "This operation was replaced by a newer account update."])
        }
    }

    private func refreshStatus(for account: AccountConfig, generation: Int) async {
        let (status, updatedConfig) = await APIClient.shared.fetchQuota(for: account)
        guard generation == refreshGeneration else {
            AppLogger.log("Discarded stale quota result for \(account.label)")
            return
        }

        statuses[status.id] = status
        if let updated = updatedConfig,
           let idx = config.accounts.firstIndex(where: { $0.id == updated.id }) {
            config.accounts[idx] = updated
            ConfigManager.shared.save(config)
        }

        lastRefreshedAt = Date()
        onIconUpdate?()
    }

    public func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        AppLogger.log("Polling all quotas...")

        let generation = refreshGeneration
        let currentAccounts = config.accounts
        var updatedConfigs: [AccountConfig] = []
        var configChanged = false

        // Run fetches in parallel using TaskGroup
        await withTaskGroup(of: (QuotaStatus, AccountConfig?).self) { group in
            for account in currentAccounts {
                group.addTask {
                    return await APIClient.shared.fetchQuota(for: account)
                }
            }

            for await (status, updatedConfig) in group {
                guard generation == self.refreshGeneration else {
                    AppLogger.log("Discarded stale quota result for account id \(status.id)")
                    continue
                }
                guard self.config.accounts.contains(where: { $0.id == status.id }) else {
                    continue
                }

                self.statuses[status.id] = status
                if let updated = updatedConfig {
                    updatedConfigs.append(updated)
                    configChanged = true
                }
            }
        }

        // Save back any updated tokens (Google refresh / Codex rotated tokens)
        if generation == refreshGeneration, configChanged {
            for updated in updatedConfigs {
                if let idx = config.accounts.firstIndex(where: { $0.id == updated.id }) {
                    config.accounts[idx] = updated
                }
            }
            ConfigManager.shared.save(config)
        }

        isRefreshing = false
        if generation == refreshGeneration {
            lastRefreshedAt = Date()
            onIconUpdate?()
        }
    }

    public func updateAccountLabel(id: String, newLabel: String) {
        if let idx = config.accounts.firstIndex(where: { $0.id == id }) {
            config.accounts[idx].label = newLabel
            ConfigManager.shared.save(config)
        }
    }

    public func updateAccountTokens(id: String, accessToken: String, refreshToken: String, idToken: String? = nil, accountId: String? = nil, email: String? = nil) {
        if let idx = config.accounts.firstIndex(where: { $0.id == id }) {
            invalidateInFlightRefreshes()
            config.accounts[idx].accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            config.accounts[idx].refreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if let idToken = idToken {
                config.accounts[idx].idToken = idToken.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            config.accounts[idx].accountId = accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let email = email {
                config.accounts[idx].email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            config.accounts[idx].expiresAt = nil // Clear expiry to force immediate refresh
            ConfigManager.shared.save(config)

            let targetAccount = config.accounts[idx]
            let generation = refreshGeneration

            // Perform fetch immediately for this account
            Task {
                await self.refreshStatus(for: targetAccount, generation: generation)
            }
        }
    }

    @discardableResult
    public func activateCodexAccount(_ draftAccount: AccountConfig) async throws -> Bool {
        guard draftAccount.type == "codex" else {
            throw NSError(domain: "QuotaMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Only Codex accounts can be activated into Codex."])
        }
        guard config.accounts.contains(where: { $0.id == draftAccount.id }) else {
            throw NSError(domain: "QuotaMonitor", code: -2, userInfo: [NSLocalizedDescriptionKey: "This account no longer exists in LimitBank."])
        }

        invalidateInFlightRefreshes()
        let generation = refreshGeneration
        let quitCodex = try await SystemCredentialDetector.quitRunningCodexApps()
        var preparedAccount = try await APIClient.shared.prepareCodexAccountForActivation(draftAccount)
        try ensureRefreshIsCurrent(generation)
        if let email = preparedAccount.email, !email.isEmpty {
            preparedAccount.label = email
        }

        try SystemCredentialDetector.writeCodexAuthFile(for: preparedAccount)
        try ensureRefreshIsCurrent(generation)

        if let idx = config.accounts.firstIndex(where: { $0.id == preparedAccount.id }) {
            config.accounts[idx] = preparedAccount
            ConfigManager.shared.save(config)
        }

        statuses[preparedAccount.id] = QuotaStatus(id: preparedAccount.id)
        await refreshStatus(for: preparedAccount, generation: generation)
        return quitCodex
    }

    @discardableResult
    public func activateAntigravityAccount(_ draftAccount: AccountConfig) async throws -> Bool {
        guard draftAccount.type == "antigravity" else {
            throw NSError(domain: "QuotaMonitor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Only Antigravity accounts can be activated into Antigravity."])
        }
        guard config.accounts.contains(where: { $0.id == draftAccount.id }) else {
            throw NSError(domain: "QuotaMonitor", code: -4, userInfo: [NSLocalizedDescriptionKey: "This account no longer exists in LimitBank."])
        }

        invalidateInFlightRefreshes()
        let generation = refreshGeneration
        let quitAntigravity = try await SystemCredentialDetector.quitRunningAntigravityApps()
        var preparedAccount = try await APIClient.shared.prepareAntigravityAccountForActivation(draftAccount)
        try ensureRefreshIsCurrent(generation)
        if let email = preparedAccount.email, !email.isEmpty {
            preparedAccount.label = email
        }

        try SystemCredentialDetector.writeAntigravityKeychain(for: preparedAccount)
        try ensureRefreshIsCurrent(generation)

        if let idx = config.accounts.firstIndex(where: { $0.id == preparedAccount.id }) {
            config.accounts[idx] = preparedAccount
            ConfigManager.shared.save(config)
        }

        statuses[preparedAccount.id] = QuotaStatus(id: preparedAccount.id)
        await refreshStatus(for: preparedAccount, generation: generation)
        return quitAntigravity
    }

    public func addAccount(type: String, label: String) -> String {
        let newAccount = AccountConfig(type: type, label: label)
        config.accounts.append(newAccount)
        if config.selectedAccountId == nil {
            config.selectedAccountId = newAccount.id
        }
        ConfigManager.shared.save(config)
        return newAccount.id
    }

    public func deleteAccount(id: String) {
        invalidateInFlightRefreshes()
        config.accounts.removeAll(where: { $0.id == id })
        if config.selectedAccountId == id {
            config.selectedAccountId = config.accounts.first?.id
        }
        statuses.removeValue(forKey: id)
        ConfigManager.shared.save(config)
        onIconUpdate?()
    }

    public func moveAccount(fromOffsets source: IndexSet, toOffset destination: Int) {
        config.accounts.move(fromOffsets: source, toOffset: destination)
        ConfigManager.shared.save(config)
        onIconUpdate?()
    }

    public func updateMenuBarStyle(_ style: String) {
        config.menuBarStyle = style
        ConfigManager.shared.save(config)
        onIconUpdate?()
    }

    public func updateRefreshInterval(_ interval: Int) {
        config.refreshInterval = interval
        ConfigManager.shared.save(config)
        stopPolling()
        startPolling()
    }

    public func autoDetectAllCredentials() {
        var changed = false
        for (idx, acc) in config.accounts.enumerated() {
            let accEmail = acc.email?.lowercased() ?? ""

            if acc.type == "codex" {
                if let detected = SystemCredentialDetector.detectCodex() {
                    let detEmail = detected.email?.lowercased() ?? ""
                    if accEmail == detEmail || accEmail.isEmpty {
                        config.accounts[idx].accessToken = detected.accessToken
                        config.accounts[idx].refreshToken = detected.refreshToken
                        config.accounts[idx].idToken = detected.idToken
                        if let accId = detected.accountId {
                            config.accounts[idx].accountId = accId
                        }
                        if let email = detected.email {
                            config.accounts[idx].email = email
                            config.accounts[idx].label = email
                        }
                        config.accounts[idx].expiresAt = nil // clear expiry
                        changed = true
                    }
                }
            } else if acc.type == "antigravity" {
                if let detected = SystemCredentialDetector.detectAntigravity() {
                    let detEmail = detected.email?.lowercased() ?? ""
                    if accEmail == detEmail || accEmail.isEmpty {
                        config.accounts[idx].accessToken = detected.accessToken
                        config.accounts[idx].refreshToken = detected.refreshToken
                        config.accounts[idx].idToken = detected.idToken
                        if let email = detected.email {
                            config.accounts[idx].email = email
                            config.accounts[idx].label = email
                        }
                        config.accounts[idx].expiresAt = nil // clear expiry
                        changed = true
                    }
                }
            }
        }

        if changed {
            invalidateInFlightRefreshes()
            ConfigManager.shared.save(config)
            Task {
                await refreshAll()
            }
        }
    }
}

public class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    private var plistURL: URL {
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryDir.appendingPathComponent("LaunchAgents/com.dendyelo.LimitBank.plist")
    }

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            guard let execPath = Bundle.main.executablePath else { return }
            let plistContent: [String: Any] = [
                "Label": "com.dendyelo.LimitBank",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]

            let launchAgentsDir = plistURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

            let data = try? PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
            try? data?.write(to: plistURL)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
