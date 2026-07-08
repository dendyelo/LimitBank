import Foundation

public struct QuotaStatus: Identifiable, Codable {
    public var id: String // Matches AccountConfig.id
    public var hoursUsedPercent: Double?
    public var hoursResetAt: Date?
    public var weeklyUsedPercent: Double?
    public var weeklyResetAt: Date?
    public var credits: Double?
    public var plan: String?
    public var error: String?
    public var lastChecked: Date
    
    // Antigravity: separate Gemini vs Claude/GPT (3p) quotas
    public var geminiHoursUsedPercent: Double?
    public var geminiHoursResetAt: Date?
    public var geminiWeeklyUsedPercent: Double?
    public var geminiWeeklyResetAt: Date?
    public var thirdPartyHoursUsedPercent: Double?
    public var thirdPartyHoursResetAt: Date?
    public var thirdPartyWeeklyUsedPercent: Double?
    public var thirdPartyWeeklyResetAt: Date?
    
    // Codex: rate-limit reset credits (bonus tickets to reset message cap)
    public var codexResetCreditsCount: Int?
    public var codexResetCreditsExpiry: Date?
    
    public init(id: String, hoursUsedPercent: Double? = nil, hoursResetAt: Date? = nil, weeklyUsedPercent: Double? = nil, weeklyResetAt: Date? = nil, credits: Double? = nil, plan: String? = nil, error: String? = nil, lastChecked: Date = Date(),
                geminiHoursUsedPercent: Double? = nil, geminiHoursResetAt: Date? = nil, geminiWeeklyUsedPercent: Double? = nil, geminiWeeklyResetAt: Date? = nil,
                thirdPartyHoursUsedPercent: Double? = nil, thirdPartyHoursResetAt: Date? = nil, thirdPartyWeeklyUsedPercent: Double? = nil, thirdPartyWeeklyResetAt: Date? = nil,
                codexResetCreditsCount: Int? = nil, codexResetCreditsExpiry: Date? = nil) {
        self.id = id
        self.hoursUsedPercent = hoursUsedPercent
        self.hoursResetAt = hoursResetAt
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetAt = weeklyResetAt
        self.credits = credits
        self.plan = plan
        self.error = error
        self.lastChecked = lastChecked
        self.geminiHoursUsedPercent = geminiHoursUsedPercent
        self.geminiHoursResetAt = geminiHoursResetAt
        self.geminiWeeklyUsedPercent = geminiWeeklyUsedPercent
        self.geminiWeeklyResetAt = geminiWeeklyResetAt
        self.thirdPartyHoursUsedPercent = thirdPartyHoursUsedPercent
        self.thirdPartyHoursResetAt = thirdPartyHoursResetAt
        self.thirdPartyWeeklyUsedPercent = thirdPartyWeeklyUsedPercent
        self.thirdPartyWeeklyResetAt = thirdPartyWeeklyResetAt
        self.codexResetCreditsCount = codexResetCreditsCount
        self.codexResetCreditsExpiry = codexResetCreditsExpiry
    }
}

public class APIClient {
    public static let shared = APIClient()
    
    private var activeRefreshes = Set<String>()
    private let refreshQueue = DispatchQueue(label: "com.limitbank.apiclient")
    
    private let googleClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private let googleClientSecret = "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"
    private let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    
    private init() {}
    
    /// Checks and refreshes tokens if necessary, then fetches the current quota.
    /// Returns the quota status and any updated account config (e.g. rotated refresh token).
    public func fetchQuota(for account: AccountConfig) async -> (QuotaStatus, AccountConfig?) {
        let isAlreadyRefreshing = refreshQueue.sync {
            if activeRefreshes.contains(account.id) {
                return true
            }
            activeRefreshes.insert(account.id)
            return false
        }
        
        if isAlreadyRefreshing {
            return (QuotaStatus(id: account.id, error: "Auth: Refresh in progress"), nil)
        }
        
        defer {
            refreshQueue.sync {
                _ = activeRefreshes.remove(account.id)
            }
        }
        
        var activeAccount = account
        var configUpdated = false
        
        // 1. Handle token refreshing if needed
        if account.type == "antigravity" {
            // Antigravity (Google OAuth)
            if shouldRefresh(expiresAt: account.expiresAt, token: account.accessToken) {
                if !account.refreshToken.isEmpty {
                    do {
                        let (newAccess, newExpiresIn) = try await refreshGoogleToken(refreshToken: account.refreshToken)
                        activeAccount.accessToken = newAccess
                        activeAccount.expiresAt = Date().addingTimeInterval(newExpiresIn)
                        configUpdated = true
                        AppLogger.log("Successfully refreshed Antigravity Google token for: \(account.label)")
                    } catch {
                        return (QuotaStatus(id: account.id, error: "Auth: Google Token Refresh failed: \(error.localizedDescription)"), nil)
                    }
                } else if account.accessToken.isEmpty {
                    return (QuotaStatus(id: account.id, error: "Configuration: Missing Tokens"), nil)
                }
            }
        } else if account.type == "codex" {
            // Codex (OpenAI OAuth)
            // Codex tokens are shorter lived or require refresh token rotation
            if shouldRefresh(expiresAt: account.expiresAt, token: account.accessToken) {
                if !account.refreshToken.isEmpty {
                    do {
                        let refreshResp = try await refreshCodexToken(refreshToken: account.refreshToken)
                        activeAccount.accessToken = refreshResp.access_token
                        activeAccount.refreshToken = refreshResp.refresh_token
                        activeAccount.expiresAt = Date().addingTimeInterval(Double(refreshResp.expires_in))
                        if let idToken = refreshResp.id_token,
                           let email = SystemCredentialDetector.parseJWTClaim(idToken, claim: "email") {
                            activeAccount.email = email
                        }
                        configUpdated = true
                        AppLogger.log("Successfully refreshed Codex OpenAI token (rotated) for: \(account.label)")
                        syncRotatedTokensToSystemFiles(activeAccount)
                    } catch {
                        return (QuotaStatus(id: account.id, error: "Auth: OpenAI Token Refresh failed: \(error.localizedDescription)"), nil)
                    }
                } else if account.accessToken.isEmpty {
                    return (QuotaStatus(id: account.id, error: "Configuration: Missing Access Token"), nil)
                }
            }
        }
        
        // Extract email as fallback if it is missing
        if activeAccount.email == nil || activeAccount.email?.isEmpty == true {
            if activeAccount.type == "codex" {
                if let email = SystemCredentialDetector.parseJWTClaim(activeAccount.accessToken, claim: "email") {
                    activeAccount.email = email
                    configUpdated = true
                }
            } else if activeAccount.type == "antigravity" {
                if let email = await APIClient.fetchGoogleEmail(accessToken: activeAccount.accessToken) {
                    activeAccount.email = email
                    configUpdated = true
                }
            }
        }
        
        // 2. Fetch actual Quota Data
        do {
            let status: QuotaStatus
            if activeAccount.type == "antigravity" {
                status = try await fetchAntigravityQuota(account: activeAccount)
            } else {
                status = try await fetchCodexQuota(account: activeAccount)
            }
            return (status, configUpdated ? activeAccount : nil)
        } catch {
            return (QuotaStatus(id: account.id, error: error.localizedDescription), configUpdated ? activeAccount : nil)
        }
    }
    
    private func shouldRefresh(expiresAt: Date?, token: String) -> Bool {
        if token.isEmpty { return true }
        guard let expiresAt = expiresAt else { return true } // If no expiry is stored, assume we need to refresh to get one
        // Refresh if expired or expiring in less than 5 minutes
        return expiresAt.timeIntervalSinceNow < 300
    }
    
    // MARK: - Google OAuth Token Refresh (Antigravity)
    private func refreshGoogleToken(refreshToken: String) async throws -> (String, Double) {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": googleClientID,
            "client_secret": googleClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = parameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token refresh returned status \(httpResponse.statusCode): \(errorMsg)"])
        }
        
        struct GoogleTokenResponse: Codable {
            let access_token: String
            let expires_in: Double
        }
        
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return (tokenResponse.access_token, tokenResponse.expires_in)
    }
    
    private static func fetchGoogleEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            struct GoogleUserInfo: Codable {
                let email: String?
            }
            
            let decoded = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
            return decoded.email
        } catch {
            return nil
        }
    }
    
    // MARK: - OpenAI OAuth Token Refresh (Codex)
    private struct CodexTokenResponse: Codable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let id_token: String?
    }
    
    private func refreshCodexToken(refreshToken: String) async throws -> CodexTokenResponse {
        let url = URL(string: "https://auth.openai.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": codexClientID,
            "scope": "openid profile email offline_access"
        ]
        
        let bodyString = parameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Codex token refresh returned status \(httpResponse.statusCode): \(errorMsg)"])
        }
        
        return try JSONDecoder().decode(CodexTokenResponse.self, from: data)
    }
    
    // MARK: - Quota Fetchers (Antigravity)
    private func fetchAntigravityQuota(account: AccountConfig) async throws -> QuotaStatus {
        let baseURLs = [
            "https://cloudcode-pa.googleapis.com",
            "https://daily-cloudcode-pa.googleapis.com"
        ]
        
        var summaryData: Data? = nil
        var fetchError: Error? = nil
        
        // Try each base URL
        for base in baseURLs {
            guard let url = URL(string: base + "/v1internal:retrieveUserQuotaSummary") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
            request.httpBody = "{}".data(using: .utf8)
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
                    }
                    if (200..<300).contains(httpResponse.statusCode) {
                        summaryData = data
                        break
                    }
                }
            } catch {
                fetchError = error
            }
        }
        
        if summaryData == nil {
            throw fetchError ?? NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to Antigravity API"])
        }
        
        // Parse Antigravity response
        struct Bucket: Codable {
            let bucketId: String?
            let remainingFraction: Double?
            let resetTime: String?
        }
        struct Group: Codable {
            let buckets: [Bucket]?
        }
        struct ResponseRoot: Codable {
            let groups: [Group]?
        }
        struct Envelope: Codable {
            let response: ResponseRoot?
            let groups: [Group]?
        }
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: summaryData!)
        let groups = envelope.response?.groups ?? envelope.groups ?? []
        
        var hoursUsed: Double? = nil
        var hoursReset: Date? = nil
        var weeklyUsed: Double? = nil
        var weeklyReset: Date? = nil
        
        // Separate Gemini vs 3P (Claude/GPT)
        var geminiHoursUsed: Double? = nil
        var geminiHoursReset: Date? = nil
        var geminiWeeklyUsed: Double? = nil
        var geminiWeeklyReset: Date? = nil
        var tpHoursUsed: Double? = nil
        var tpHoursReset: Date? = nil
        var tpWeeklyUsed: Double? = nil
        var tpWeeklyReset: Date? = nil
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        func parseDate(_ str: String?) -> Date? {
            guard let str = str else { return nil }
            if let date = dateFormatter.date(from: str) {
                return date
            }
            // Fallback for standard ISO8601
            let fallbackFormatter = ISO8601DateFormatter()
            return fallbackFormatter.date(from: str)
        }
        
        for bucket in groups.flatMap({ $0.buckets ?? [] }) {
            guard let id = bucket.bucketId else { continue }
            guard let fraction = bucket.remainingFraction else { continue }
            
            let usedPercent = (1.0 - fraction) * 100.0
            let resetDate = parseDate(bucket.resetTime)
            
            switch id {
            case "gemini-5h":
                geminiHoursUsed = usedPercent
                geminiHoursReset = resetDate
                hoursUsed = max(hoursUsed ?? 0.0, usedPercent)
                if hoursReset == nil || (resetDate != nil && resetDate! < hoursReset!) {
                    hoursReset = resetDate
                }
            case "3p-5h":
                tpHoursUsed = usedPercent
                tpHoursReset = resetDate
                hoursUsed = max(hoursUsed ?? 0.0, usedPercent)
                if hoursReset == nil || (resetDate != nil && resetDate! < hoursReset!) {
                    hoursReset = resetDate
                }
            case "gemini-weekly":
                geminiWeeklyUsed = usedPercent
                geminiWeeklyReset = resetDate
                weeklyUsed = max(weeklyUsed ?? 0.0, usedPercent)
                if weeklyReset == nil || (resetDate != nil && resetDate! < weeklyReset!) {
                    weeklyReset = resetDate
                }
            case "3p-weekly":
                tpWeeklyUsed = usedPercent
                tpWeeklyReset = resetDate
                weeklyUsed = max(weeklyUsed ?? 0.0, usedPercent)
                if weeklyReset == nil || (resetDate != nil && resetDate! < weeklyReset!) {
                    weeklyReset = resetDate
                }
            default:
                break
            }
        }
        
        // Fetch Plan Name (best-effort)
        var planName: String? = nil
        for base in baseURLs {
            guard let url = URL(string: base + "/v1internal:loadCodeAssist") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("agy", forHTTPHeaderField: "User-Agent")
            request.httpBody = "{}".data(using: .utf8)
            request.timeoutInterval = 5
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                struct Tier: Codable { let name: String? }
                struct LoadResponse: Codable {
                    let currentTier: Tier?
                    let paidTier: Tier?
                }
                if let loadResp = try? decoder.decode(LoadResponse.self, from: data) {
                    planName = loadResp.paidTier?.name ?? loadResp.currentTier?.name
                    break
                }
            }
        }
        
        return QuotaStatus(
            id: account.id,
            hoursUsedPercent: hoursUsed,
            hoursResetAt: hoursReset,
            weeklyUsedPercent: weeklyUsed,
            weeklyResetAt: weeklyReset,
            plan: planName ?? "Free",
            geminiHoursUsedPercent: geminiHoursUsed,
            geminiHoursResetAt: geminiHoursReset,
            geminiWeeklyUsedPercent: geminiWeeklyUsed,
            geminiWeeklyResetAt: geminiWeeklyReset,
            thirdPartyHoursUsedPercent: tpHoursUsed,
            thirdPartyHoursResetAt: tpHoursReset,
            thirdPartyWeeklyUsedPercent: tpWeeklyUsed,
            thirdPartyWeeklyResetAt: tpWeeklyReset
        )
    }
    
    // MARK: - Quota Fetchers (Codex)
    private func fetchCodexQuota(account: AccountConfig) async throws -> QuotaStatus {
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("onwatch/1.0", forHTTPHeaderField: "User-Agent")
        if let accountId = account.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "X-Account-Id")
            request.setValue(accountId, forHTTPHeaderField: "ChatClaude-Account-Id")
        }
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        if httpResponse.statusCode != 200 {
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned error status \(httpResponse.statusCode)"])
        }
        
        // Parse Codex response
        struct CodexWindow: Codable {
            let used_percent: Double?
            let reset_at: Int64?
        }
        struct CodexRateLimit: Codable {
            let primary_window: CodexWindow?
            let secondary_window: CodexWindow?
        }
        struct CodexBalance: Codable {
            let value: Double?
        }
        struct CodexCredits: Codable {
            let balance: CodexBalanceValue?
        }
        struct CodexResponse: Codable {
            let plan_type: String?
            let rate_limit: CodexRateLimit?
            let credits: CodexCredits?
        }
        
        // Handle flexible CodexBalanceValue
        enum CodexBalanceValue: Codable {
            case double(Double)
            case string(String)
            case dict(CodexBalance)
            case null
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .null
                } else if let d = try? container.decode(Double.self) {
                    self = .double(d)
                } else if let s = try? container.decode(String.self) {
                    self = .string(s)
                } else if let dict = try? container.decode(CodexBalance.self) {
                    self = .dict(dict)
                } else {
                    self = .null
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .double(let d): try container.encode(d)
                case .string(let s): try container.encode(s)
                case .dict(let dict): try container.encode(dict)
                case .null: try container.encodeNil()
                }
            }
        }
        
        let codexResp = try JSONDecoder().decode(CodexResponse.self, from: data)
        
        var hoursUsed: Double? = nil
        var hoursReset: Date? = nil
        var weeklyUsed: Double? = nil
        var weeklyReset: Date? = nil
        
        // Codex windows: primary is typically 5h, secondary is weekly
        if let primary = codexResp.rate_limit?.primary_window {
            hoursUsed = primary.used_percent
            if let resetUnix = primary.reset_at {
                hoursReset = Date(timeIntervalSince1970: TimeInterval(resetUnix))
            }
        }
        
        if let secondary = codexResp.rate_limit?.secondary_window {
            weeklyUsed = secondary.used_percent
            if let resetUnix = secondary.reset_at {
                weeklyReset = Date(timeIntervalSince1970: TimeInterval(resetUnix))
            }
        }
        
        
        var creditsVal: Double? = nil
        if let credits = codexResp.credits?.balance {
            switch credits {
            case .double(let d): creditsVal = d
            case .string(let s): creditsVal = Double(s)
            case .dict(let d): creditsVal = d.value
            case .null: break
            }
        }
        
        // Fetch Rate Limit Reset Credits (best-effort)
        var resetCreditsCount: Int? = nil
        var resetCreditsExpiry: Date? = nil
        
        let resetUrl = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        var resetRequest = URLRequest(url: resetUrl)
        resetRequest.httpMethod = "GET"
        resetRequest.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        resetRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        resetRequest.setValue("onwatch/1.0", forHTTPHeaderField: "User-Agent")
        resetRequest.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        resetRequest.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountId = account.accountId, !accountId.isEmpty {
            resetRequest.setValue(accountId, forHTTPHeaderField: "X-Account-Id")
            resetRequest.setValue(accountId, forHTTPHeaderField: "ChatClaude-Account-Id")
            resetRequest.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        resetRequest.timeoutInterval = 5
        
        if let (resetData, resetResponse) = try? await URLSession.shared.data(for: resetRequest),
           let httpResetResponse = resetResponse as? HTTPURLResponse,
           (200..<300).contains(httpResetResponse.statusCode) {
            
            struct ResetCredit: Codable {
                let status: String?
                let expires_at: String?
            }
            struct ResetCreditsResponse: Codable {
                let available_count: Int?
                let credits: [ResetCredit]?
            }
            
            let resetDecoder = JSONDecoder()
            if let decodedResets = try? resetDecoder.decode(ResetCreditsResponse.self, from: resetData) {
                resetCreditsCount = decodedResets.available_count
                
                // Find the earliest expiration date among active/granted credits
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                var earliestExpiry: Date? = nil
                if let credits = decodedResets.credits {
                    for credit in credits {
                        let statusStr = credit.status?.lowercased()
                        if statusStr == "granted" || statusStr == "active" || statusStr == nil {
                            if let expiryStr = credit.expires_at {
                                let expiryDate = dateFormatter.date(from: expiryStr) ?? ISO8601DateFormatter().date(from: expiryStr)
                                if let exp = expiryDate {
                                    if earliestExpiry == nil || exp < earliestExpiry! {
                                        earliestExpiry = exp
                                    }
                                }
                            }
                        }
                    }
                }
                resetCreditsExpiry = earliestExpiry
            }
        }
        
        return QuotaStatus(
            id: account.id,
            hoursUsedPercent: hoursUsed,
            hoursResetAt: hoursReset,
            weeklyUsedPercent: weeklyUsed,
            weeklyResetAt: weeklyReset,
            credits: creditsVal,
            plan: codexResp.plan_type?.capitalized ?? "Pro",
            codexResetCreditsCount: resetCreditsCount,
            codexResetCreditsExpiry: resetCreditsExpiry
        )
    }
    
    public static func ParseIDTokenUserID(_ idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
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
        
        if let authClaims = json["https://api.openai.com/auth"] as? [String: Any] {
            if let userId = authClaims["chatgpt_user_id"] as? String {
                return userId.trimmingCharacters(in: .whitespaces)
            }
            if let userId = authClaims["user_id"] as? String {
                return userId.trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func syncRotatedTokensToSystemFiles(_ account: AccountConfig) {
        guard account.type == "codex" else { return }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".codex/auth.json")
        
        guard FileManager.default.fileExists(atPath: authURL.path),
              let data = try? Data(contentsOf: authURL) else { return }
              
        struct CodexAuthTokens: Codable {
            let access_token: String?
            let refresh_token: String?
            let id_token: String?
            let account_id: String?
        }
        struct CodexAuth: Codable {
            var tokens: CodexAuthTokens?
        }
        
        guard var auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
              let tokens = auth.tokens,
              let idToken = tokens.id_token,
              let systemEmail = SystemCredentialDetector.parseJWTClaim(idToken, claim: "email") else { return }
              
        if systemEmail.lowercased() == account.email?.lowercased() {
            let updatedTokens = CodexAuthTokens(
                access_token: account.accessToken,
                refresh_token: account.refreshToken,
                id_token: tokens.id_token,
                account_id: tokens.account_id
            )
            auth.tokens = updatedTokens
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let encodedData = try? encoder.encode(auth) {
                try? encodedData.write(to: authURL, options: .atomic)
                AppLogger.log("Synchronized rotated Codex tokens back to ~/.codex/auth.json")
            }
        }
    }
}
