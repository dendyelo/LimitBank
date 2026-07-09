import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    @StateObject private var monitor = QuotaMonitor.shared
    @State private var draggedAccount: AccountConfig? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(monitor.config.accounts) { account in
                        let status = monitor.statuses[account.id] ?? QuotaStatus(id: account.id)
                        let isSelected = monitor.config.selectedAccountId == account.id

                        AccountRowView(
                            account: account,
                            status: status,
                            isSelected: isSelected,
                            onSelect: {
                                monitor.selectAccount(id: account.id)
                            }
                        )
                        .onDrag {
                            self.draggedAccount = account
                            return NSItemProvider(object: account.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: AccountDropDelegate(
                            item: account,
                            draggedItem: $draggedAccount,
                            monitor: monitor
                        ))
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 650)
        }
        .background(Color.clear)
    }
}

struct MenuAccountRowView: View {
    @ObservedObject var monitor = QuotaMonitor.shared
    let accountId: String
    let onSelect: () -> Void

    var body: some View {
        if let account = monitor.config.accounts.first(where: { $0.id == accountId }) {
            let status = monitor.statuses[accountId] ?? QuotaStatus(id: accountId)
            let isSelected = monitor.config.selectedAccountId == accountId

            AccountRowView(
                account: account,
                status: status,
                isSelected: isSelected,
                onSelect: onSelect
            )
        }
    }
}

struct AccountRowView: View {
    let account: AccountConfig
    let status: QuotaStatus
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: statusColor.opacity(0.5), radius: 2)
                    }

                    HStack(spacing: 4) {
                        Text(account.type == "codex" ? "Codex" : "Antigravity")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(status.plan ?? "—")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
            }

            if let error = status.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                    Text(error.contains("Unauthorized") ? "UNAUTHORIZED" : error.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .padding(.top, 2)
            } else if account.type == "antigravity" {
                // Antigravity: separate Gemini and Claude/GPT sections
                VStack(spacing: 10) {
                    // Gemini Models
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gemini")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        QuotaBarView(
                            icon: "clock",
                            label: "5H",
                            usedPercent: status.geminiHoursUsedPercent,
                            resetAt: status.geminiHoursResetAt
                        )

                        QuotaBarView(
                            icon: "calendar",
                            label: "WK",
                            usedPercent: status.geminiWeeklyUsedPercent,
                            resetAt: status.geminiWeeklyResetAt
                        )
                    }

                    // Claude & GPT Models
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Claude / GPT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        QuotaBarView(
                            icon: "clock",
                            label: "5H",
                            usedPercent: status.thirdPartyHoursUsedPercent,
                            resetAt: status.thirdPartyHoursResetAt
                        )

                        QuotaBarView(
                            icon: "calendar",
                            label: "WK",
                            usedPercent: status.thirdPartyWeeklyUsedPercent,
                            resetAt: status.thirdPartyWeeklyResetAt
                        )
                    }
                }
            } else {
                // Codex: single combined view
                VStack(spacing: 8) {
                    QuotaBarView(
                        icon: "clock",
                        label: "5H",
                        usedPercent: status.hoursUsedPercent,
                        resetAt: status.hoursResetAt
                    )

                    QuotaBarView(
                        icon: "calendar",
                        label: "WK",
                        usedPercent: status.weeklyUsedPercent,
                        resetAt: status.weeklyResetAt
                    )

                    if let credits = status.credits {
                        HStack(spacing: 6) {
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("CREDIT")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", credits))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 2)
                    }

                    if let resets = status.codexResetCreditsCount, resets > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "ticket")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("LIMIT RESETS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(resets) available")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            if let expiry = status.codexResetCreditsExpiry {
                                Text("(exp \(QuotaBarView.timeRemaining(from: expiry) ?? ""))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.06) : Color.primary.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var statusColor: Color {
        if status.error != nil {
            return .red
        } else if status.hoursUsedPercent == nil {
            return .gray
        } else {
            return .emerald
        }
    }
}

struct QuotaBarView: View {
    let icon: String
    let label: String
    let usedPercent: Double?
    let resetAt: Date?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 38, alignment: .leading)

            // Thin progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)

                    if let used = usedPercent {
                        let remaining = max(0.0, 100.0 - used)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.primary.opacity(0.65))
                            .frame(width: geo.size.width * CGFloat(remaining / 100.0), height: 5)
                    }
                }
            }
            .frame(height: 5)

            // Value & Reset Timer
            HStack(spacing: 4) {
                if let used = usedPercent {
                    let remaining = max(0.0, 100.0 - used)
                    Text(String(format: "%.0f%%", remaining))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)

                    if let resetStr = QuotaBarView.timeRemaining(from: resetAt), !resetStr.isEmpty {
                        Text("• \(resetStr)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                } else {
                    Text("NO DATA")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
    }

    static func timeRemaining(from date: Date?) -> String? {
        guard let date = date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 {
            return "reset"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var monitor: QuotaMonitor
    @State private var selectedAccountId: String? = nil

    var body: some View {
        SettingsView(
            showingSettings: .constant(true),
            selectedAccountId: $selectedAccountId
        )
        .environmentObject(monitor)
        .onAppear {
            selectedAccountId = "__general__"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var monitor: QuotaMonitor
    @Binding var showingSettings: Bool
    @Binding var selectedAccountId: String?

    @State private var labelText: String = ""
    @State private var accessTokenText: String = ""
    @State private var refreshTokenText: String = ""
    @State private var idTokenText: String = ""
    @State private var accountIdText: String = ""
    @State private var emailText: String = ""
    @State private var showDetectAlert = false
    @State private var detectAlertMessage = ""
    @State private var draggedAccount: AccountConfig? = nil
    @State private var isActivatingCodex = false
    @State private var isActivatingAntigravity = false
    @State private var isLoggingInCodex = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAccountId) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("General")
                        .font(.system(size: 13, weight: .medium))
                }
                .tag("__general__")

                Section("Accounts") {
                    ForEach(monitor.config.accounts) { acc in
                        HStack(spacing: 8) {
                            Image(systemName: acc.type == "codex" ? "terminal" : "sparkle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(acc.displayName)
                                    .font(.system(size: 13))
                                    .lineLimit(1)

                                Text(acc.type == "codex" ? "Codex" : "Antigravity")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(acc.id)
                        .contextMenu {
                            if let idx = monitor.config.accounts.firstIndex(where: { $0.id == acc.id }) {
                                Button("Move Up") {
                                    if idx > 0 {
                                        withAnimation {
                                            monitor.moveAccount(fromOffsets: IndexSet(integer: idx), toOffset: idx - 1)
                                        }
                                    }
                                }
                                .disabled(idx == 0)

                                Button("Move Down") {
                                    if idx < monitor.config.accounts.count - 1 {
                                        withAnimation {
                                            monitor.moveAccount(fromOffsets: IndexSet(integer: idx), toOffset: idx + 2)
                                        }
                                    }
                                }
                                .disabled(idx == monitor.config.accounts.count - 1)

                                Divider()
                            }

                            if monitor.config.accounts.count > 1 {
                                Button("Delete", role: .destructive) {
                                    monitor.deleteAccount(id: acc.id)
                                    if selectedAccountId == acc.id {
                                        selectedAccountId = "__general__"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Menu {
                            Button("Codex Account") {
                                let newId = monitor.addAccount(type: "codex", label: "New Codex")
                                selectedAccountId = newId
                            }
                            Button("Antigravity Account") {
                                let newId = monitor.addAccount(type: "antigravity", label: "New Antigravity")
                                selectedAccountId = newId
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24, height: 24)

                        Button(action: {
                            if let id = selectedAccountId, id != "__general__", monitor.config.accounts.count > 1 {
                                monitor.deleteAccount(id: id)
                                selectedAccountId = "__general__"
                            }
                        }) {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(monitor.config.accounts.count <= 1)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if selectedAccountId == "__general__" {
                    Form {
                        Section("Preferences") {
                            Toggle("Launch at Login", isOn: Binding(
                                get: { LaunchAtLoginManager.shared.isEnabled },
                                set: { LaunchAtLoginManager.shared.setEnabled($0) }
                            ))

                            Picker("Auto-Refresh Interval", selection: Binding(
                                get: { monitor.config.refreshInterval ?? 60 },
                                set: { monitor.updateRefreshInterval($0) }
                            )) {
                                Text("1 Minute").tag(60)
                                Text("5 Minutes").tag(300)
                                Text("10 Minutes").tag(600)
                                Text("15 Minutes").tag(900)
                                Text("30 Minutes").tag(1800)
                                Text("1 Hour").tag(3600)
                            }

                            Picker("Menu Bar Style", selection: Binding(
                                get: { monitor.config.menuBarStyle ?? "bars" },
                                set: { monitor.updateMenuBarStyle($0) }
                            )) {
                                Text("Progress Bars").tag("bars")
                                Text("Percentage Text").tag("percentage")
                                Text("Both Icon and Text").tag("both")
                            }
                        }

                    }
                    .formStyle(.grouped)
                    .padding(.vertical, 8)
                } else if let selectedId = selectedAccountId,
                          let account = monitor.config.accounts.first(where: { $0.id == selectedId }) {

                    ScrollView {
                        Form {
                            Section("General") {
                                TextField("Username / Email", text: $emailText)
                            }

                            Section("Quick Setup") {
                                if account.type == "codex" {
                                    Button(action: {
                                        Task { @MainActor in
                                            isLoggingInCodex = true
                                            defer { isLoggingInCodex = false }

                                            do {
                                                try await SystemCredentialDetector.loginCodexAndWait()
                                                guard let detected = SystemCredentialDetector.detectCodex() else {
                                                    detectAlertMessage = "Codex login finished, but no active session was found in ~/.codex/auth.json."
                                                    showDetectAlert = true
                                                    return
                                                }

                                                saveDetectedCodexCredentials(detected, to: account)
                                                detectAlertMessage = "Codex account saved to LimitBank."
                                            } catch {
                                                detectAlertMessage = "Codex login failed: \(error.localizedDescription)"
                                            }
                                            showDetectAlert = true
                                        }
                                    }) {
                                        Label(isLoggingInCodex ? "Waiting for Login..." : "Login, Import & Save", systemImage: "terminal")
                                    }
                                    .disabled(isLoggingInCodex || isActivatingCodex)

                                    Button(action: {
                                        if let detected = SystemCredentialDetector.detectCodex() {
                                            saveDetectedCodexCredentials(detected, to: account)
                                            detectAlertMessage = "Codex account imported and saved to LimitBank."
                                            showDetectAlert = true
                                        } else {
                                            detectAlertMessage = "No active Codex session found. Run 'Login, Import & Save' first."
                                            showDetectAlert = true
                                        }
                                    }) {
                                        Label("Import & Save from System Files", systemImage: "arrow.down.doc")
                                    }

                                    Button(action: {
                                        Task { @MainActor in
                                            isActivatingCodex = true
                                            defer { isActivatingCodex = false }

                                            var codexAccount = account
                                            let trimmedEmail = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            codexAccount.accessToken = accessTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            codexAccount.refreshToken = refreshTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            codexAccount.idToken = idTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? account.idToken : idTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            codexAccount.accountId = accountIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : accountIdText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            codexAccount.email = trimmedEmail.isEmpty ? account.email : trimmedEmail
                                            if !trimmedEmail.isEmpty {
                                                codexAccount.label = trimmedEmail
                                            }

                                            do {
                                                let didQuitCodex = try await monitor.activateCodexAccount(codexAccount)
                                                if didQuitCodex {
                                                    detectAlertMessage = "Codex was closed and this account is now active in ~/.codex/auth.json. You can open Codex now."
                                                } else {
                                                    detectAlertMessage = "This account is now active in ~/.codex/auth.json. You can open Codex now."
                                                }
                                            } catch {
                                                detectAlertMessage = "Failed to activate Codex account: \(error.localizedDescription)"
                                            }
                                            showDetectAlert = true
                                        }
                                    }) {
                                        Label(isActivatingCodex ? "Activating..." : "Set as Active Codex Session", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .disabled(isActivatingCodex || accessTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || refreshTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Text("Tip: To switch accounts, import each account once, then use 'Set as Active Codex Session'. LimitBank will close Codex first if it is running. Avoid signing out inside Codex, because that can revoke the saved session.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    Button(action: {
                                        OAuthServer.shared.startLoginFlow(
                                            accountType: "antigravity",
                                            accountId: account.id
                                        )
                                        detectAlertMessage = "Opening Google login. Once login finishes, this account will be saved to LimitBank automatically."
                                        showDetectAlert = true
                                    }) {
                                        Label("Login & Save with Google", systemImage: "safari")
                                    }

                                    Button(action: {
                                        if let detected = SystemCredentialDetector.detectAntigravity() {
                                            saveDetectedAntigravityCredentials(detected, to: account)
                                            detectAlertMessage = "Antigravity account imported and saved to LimitBank."
                                            showDetectAlert = true
                                        } else {
                                            detectAlertMessage = "No active Antigravity session found in Keychain. Please login in your IDE first."
                                            showDetectAlert = true
                                        }
                                    }) {
                                        Label("Import & Save from Keychain", systemImage: "key")
                                    }

                                    Button(action: {
                                        Task { @MainActor in
                                            isActivatingAntigravity = true
                                            defer { isActivatingAntigravity = false }

                                            var antigravityAccount = account
                                            let trimmedEmail = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            antigravityAccount.accessToken = accessTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            antigravityAccount.refreshToken = refreshTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            antigravityAccount.idToken = idTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? account.idToken : idTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            antigravityAccount.email = trimmedEmail.isEmpty ? account.email : trimmedEmail
                                            if !trimmedEmail.isEmpty {
                                                antigravityAccount.label = trimmedEmail
                                            }

                                            do {
                                                let didQuitAntigravity = try await monitor.activateAntigravityAccount(antigravityAccount)
                                                if didQuitAntigravity {
                                                    detectAlertMessage = "Antigravity was closed and this account is now active in Keychain. You can open Antigravity now."
                                                } else {
                                                    detectAlertMessage = "This account is now active in Keychain. You can open Antigravity now."
                                                }
                                            } catch {
                                                detectAlertMessage = "Failed to activate Antigravity account: \(error.localizedDescription)"
                                            }
                                            showDetectAlert = true
                                        }
                                    }) {
                                        Label(isActivatingAntigravity ? "Activating..." : "Activate Antigravity Session", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .disabled(isActivatingAntigravity || refreshTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Text("Tip: To switch Antigravity accounts, import each account once, then use 'Activate Antigravity Session'. LimitBank will close Antigravity first if it is running.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }

                            Section("Credentials") {
                                if account.type == "codex" {
                                    SecureField("Access Token", text: $accessTokenText)
                                    SecureField("Refresh Token", text: $refreshTokenText)
                                    TextField("Account ID (Optional)", text: $accountIdText)
                                } else {
                                    SecureField("Refresh Token", text: $refreshTokenText)
                                    SecureField("Cached Access Token (Optional)", text: $accessTokenText)
                                }
                            }
                        }
                        .formStyle(.grouped)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: selectedAccountId) {
                        loadAccountData()
                    }
                    .onChange(of: monitor.config.accounts) {
                        loadAccountData()
                    }
                    .onAppear {
                        loadAccountData()
                    }

                } else {
                    Spacer()
                    Text("Select an account to configure")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Divider()

                // Bottom Action buttons
                HStack {
                    Button("Cancel") {
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Save") {
                        if let selectedId = selectedAccountId, selectedId != "__general__" {
                            let displayLabel = emailText.isEmpty ? (monitor.config.accounts.first(where: { $0.id == selectedId })?.label ?? "Account") : emailText
                            monitor.updateAccountLabel(id: selectedId, newLabel: displayLabel)
                            monitor.updateAccountTokens(
                                id: selectedId,
                                accessToken: accessTokenText,
                                refreshToken: refreshTokenText,
                                idToken: idTokenText.isEmpty ? nil : idTokenText,
                                accountId: accountIdText.isEmpty ? nil : accountIdText,
                                email: emailText.isEmpty ? nil : emailText
                            )
                        }
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .alert(isPresented: $showDetectAlert) {
            Alert(title: Text("System Auto-Detect"), message: Text(detectAlertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func loadAccountData() {
        guard let selectedId = selectedAccountId,
              let account = monitor.config.accounts.first(where: { $0.id == selectedId }) else { return }

        labelText = account.label
        accessTokenText = account.accessToken
        refreshTokenText = account.refreshToken
        idTokenText = account.idToken ?? ""
        accountIdText = account.accountId ?? ""

        if let email = account.email, !email.isEmpty {
            emailText = email
        } else if let email = SystemCredentialDetector.parseJWTClaim(account.accessToken, claim: "email") {
            emailText = email
        } else {
            emailText = ""
        }
    }

    private func saveDetectedCodexCredentials(
        _ detected: (accessToken: String, refreshToken: String, idToken: String?, accountId: String?, email: String?),
        to account: AccountConfig
    ) {
        accessTokenText = detected.accessToken
        refreshTokenText = detected.refreshToken
        idTokenText = detected.idToken ?? ""
        accountIdText = detected.accountId ?? ""
        emailText = detected.email ?? ""

        let displayLabel = emailText.isEmpty ? account.label : emailText
        monitor.updateAccountLabel(id: account.id, newLabel: displayLabel)
        monitor.updateAccountTokens(
            id: account.id,
            accessToken: detected.accessToken,
            refreshToken: detected.refreshToken,
            idToken: detected.idToken,
            accountId: detected.accountId,
            email: detected.email
        )
    }

    private func saveDetectedAntigravityCredentials(
        _ detected: (accessToken: String, refreshToken: String, idToken: String?, email: String?),
        to account: AccountConfig
    ) {
        accessTokenText = detected.accessToken
        refreshTokenText = detected.refreshToken
        idTokenText = detected.idToken ?? ""
        emailText = detected.email ?? ""

        let displayLabel = emailText.isEmpty ? account.label : emailText
        monitor.updateAccountLabel(id: account.id, newLabel: displayLabel)
        monitor.updateAccountTokens(
            id: account.id,
            accessToken: detected.accessToken,
            refreshToken: detected.refreshToken,
            idToken: detected.idToken,
            email: detected.email
        )
    }
}

// Custom Colors Helper
extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
}

struct AccountDropDelegate: DropDelegate {
    let item: AccountConfig
    @Binding var draggedItem: AccountConfig?
    let monitor: QuotaMonitor

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem else { return }
        if dragged.id != item.id {
            let fromIndex = monitor.config.accounts.firstIndex(where: { $0.id == dragged.id }) ?? 0
            let toIndex = monitor.config.accounts.firstIndex(where: { $0.id == item.id }) ?? 0

            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                monitor.moveAccount(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
