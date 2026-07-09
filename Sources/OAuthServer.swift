import Foundation
import Network
import CryptoKit
import AppKit

extension Notification.Name {
    static let limitBankOAuthLoginDidSave = Notification.Name("LimitBankOAuthLoginDidSave")
    static let limitBankOAuthLoginDidFail = Notification.Name("LimitBankOAuthLoginDidFail")
}

enum OAuthNotificationKey {
    static let accountType = "accountType"
    static let accountId = "accountId"
    static let email = "email"
    static let error = "error"
}

public class OAuthServer {
    public static let shared = OAuthServer()
    
    private var listener: NWListener?
    private var activeVerifier: String?
    private var activeAccountType: String?
    private var activeAccountId: String?
    
    private init() {}
    
    @discardableResult
    public func startLoginFlow(accountType: String, accountId: String) -> Bool {
        // Stop any running listener first
        self.stop()
        
        self.activeAccountType = accountType
        self.activeAccountId = accountId
        
        let verifierAndChallenge = generatePKCEPair()
        self.activeVerifier = verifierAndChallenge.verifier
        
        do {
            let parameters = NWParameters.tcp
            let port = NWEndpoint.Port(integerLiteral: 12111)
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLogger.log("OAuth redirect server listening on port 12111")
                case .failed(let error):
                    AppLogger.log("OAuth redirect server failed to start: \(error)")
                    self.postLoginFailure(accountType: accountType, accountId: accountId, error: error.localizedDescription)
                    self.stop()
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener.start(queue: .main)
            
            // Open Browser to auth page
            let authURLString: String
            if accountType == "codex" {
                // OpenAI OAuth Authorize URL
                authURLString = "https://auth.openai.com/authorize?client_id=app_EMoamEEZ73f0CkXaXp7hrann&redirect_uri=http://127.0.0.1:12111/callback&response_type=code&scope=openid%20profile%20email%20offline_access&code_challenge=\(verifierAndChallenge.challenge)&code_challenge_method=S256&prompt=login"
            } else {
                // Google OAuth Authorize URL (Antigravity client details)
                authURLString = "https://accounts.google.com/o/oauth2/v2/auth?client_id=1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com&redirect_uri=http://127.0.0.1:12111/callback&response_type=code&scope=openid%20profile%20email%20https://www.googleapis.com/auth/cloud-platform&access_type=offline&prompt=consent"
            }
            
            if let url = URL(string: authURLString) {
                let didOpenBrowser = NSWorkspace.shared.open(url)
                if !didOpenBrowser {
                    self.stop()
                }
                return didOpenBrowser
            }
        } catch {
            AppLogger.log("Failed to start OAuth server: \(error)")
            postLoginFailure(accountType: accountType, accountId: accountId, error: error.localizedDescription)
        }

        self.stop()
        return false
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        activeVerifier = nil
        activeAccountType = nil
        activeAccountId = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        AppLogger.log("OAuth server: New incoming connection received.")
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                AppLogger.log("OAuth server: Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            
            if let data = data, let requestStr = String(data: data, encoding: .utf8) {
                AppLogger.log("OAuth server: Received HTTP Request (first line): \(requestStr.components(separatedBy: "\r\n").first ?? "")")
                if let code = self.parseAuthorizationCode(from: requestStr) {
                    AppLogger.log("OAuth server: Successfully parsed authorization code.")
                    self.sendSuccessResponse(to: connection)
                    
                    Task {
                        AppLogger.log("OAuth server: Starting token exchange...")
                        await self.exchangeCodeForTokens(code: code)
                        self.stop()
                    }
                } else {
                    AppLogger.log("OAuth server: Request did not contain a valid code query parameter.")
                    self.sendErrorResponse(to: connection)
                }
            } else {
                AppLogger.log("OAuth server: Received empty or invalid text data.")
                connection.cancel()
            }
        }
    }
    
    private func parseAuthorizationCode(from request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        
        let path = parts[1]
        guard let urlComponents = URLComponents(string: "http://127.0.0.1:12111" + path),
              let queryItems = urlComponents.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == "code" })?.value
    }
    
    private func sendSuccessResponse(to connection: NWConnection) {
        let html = """
        <!doctype html>
        <html>
        <head>
            <title>LimitBank Auth</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                :root {
                    color-scheme: light dark;
                    --bg: #f5f5f7;
                    --panel: rgba(255, 255, 255, 0.88);
                    --text: #1d1d1f;
                    --muted: #6e6e73;
                    --accent: #0a7d43;
                    --line: rgba(0, 0, 0, 0.08);
                }

                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg: #1f2023;
                        --panel: rgba(42, 43, 47, 0.9);
                        --text: #f5f5f7;
                        --muted: #b5b5ba;
                        --accent: #32d583;
                        --line: rgba(255, 255, 255, 0.12);
                    }
                }

                * {
                    box-sizing: border-box;
                }

                body {
                    min-height: 100vh;
                    margin: 0;
                    display: grid;
                    place-items: center;
                    padding: 28px;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                    background: var(--bg);
                    color: var(--text);
                }

                .card {
                    width: min(420px, 100%);
                    padding: 34px 30px 30px;
                    text-align: center;
                    background: var(--panel);
                    border: 1px solid var(--line);
                    border-radius: 18px;
                    box-shadow: 0 18px 50px rgba(0, 0, 0, 0.12);
                    backdrop-filter: blur(18px);
                }

                .icon {
                    position: relative;
                    width: 54px;
                    height: 54px;
                    margin: 0 auto 18px;
                    border-radius: 50%;
                    background: var(--accent);
                }

                .icon::after {
                    content: "";
                    position: absolute;
                    left: 18px;
                    top: 14px;
                    width: 15px;
                    height: 24px;
                    border: solid white;
                    border-width: 0 4px 4px 0;
                    transform: rotate(45deg);
                }

                h1 {
                    margin: 0;
                    font-size: 28px;
                    line-height: 1.15;
                    font-weight: 700;
                    letter-spacing: 0;
                }

                p {
                    margin: 12px 0 0;
                    font-size: 15px;
                    line-height: 1.5;
                    color: var(--muted);
                }

                .app {
                    margin-top: 22px;
                    padding-top: 18px;
                    border-top: 1px solid var(--line);
                    font-size: 13px;
                    font-weight: 600;
                    color: var(--muted);
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="icon" aria-hidden="true"></div>
                <h1>Log in berhasil</h1>
                <p>Silakan tutup halaman ini dan kembali ke pengaturan LimitBank.</p>
                <div class="app">LimitBank</div>
            </div>
        </body>
        </html>
        """
        
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendErrorResponse(to connection: NWConnection) {
        let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nFailed to capture authorization code."
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func exchangeCodeForTokens(code: String) async {
        guard let accountType = activeAccountType, let accountId = activeAccountId else { return }
        
        do {
            if accountType == "codex" {
                let verifier = activeVerifier ?? ""
                let tokens = try await exchangeCodexCode(code: code, verifier: verifier)
                
                await MainActor.run {
                    QuotaMonitor.shared.updateAccountTokens(
                        id: accountId,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        idToken: tokens.idToken,
                        accountId: tokens.accountId,
                        email: tokens.email
                    )
                    self.updateSavedAccountLabel(accountId: accountId, email: tokens.email)
                    self.postLoginSaved(accountType: accountType, accountId: accountId, email: tokens.email)
                }
            } else {
                let tokens = try await exchangeGoogleCode(code: code)
                
                await MainActor.run {
                    QuotaMonitor.shared.updateAccountTokens(
                        id: accountId,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        idToken: tokens.idToken,
                        email: tokens.email
                    )
                    self.updateSavedAccountLabel(accountId: accountId, email: tokens.email)
                    self.postLoginSaved(accountType: accountType, accountId: accountId, email: tokens.email)
                }
            }
        } catch {
            AppLogger.log("Failed to exchange OAuth code: \(error)")
            await MainActor.run {
                self.postLoginFailure(accountType: accountType, accountId: accountId, error: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func updateSavedAccountLabel(accountId: String, email: String?) {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedEmail.isEmpty else { return }
        QuotaMonitor.shared.updateAccountLabel(id: accountId, newLabel: trimmedEmail)
    }

    private func postLoginSaved(accountType: String, accountId: String, email: String?) {
        var userInfo: [String: String] = [
            OAuthNotificationKey.accountType: accountType,
            OAuthNotificationKey.accountId: accountId
        ]

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty {
            userInfo[OAuthNotificationKey.email] = trimmedEmail
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .limitBankOAuthLoginDidSave, object: self, userInfo: userInfo)
        }
    }

    private func postLoginFailure(accountType: String, accountId: String, error: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .limitBankOAuthLoginDidFail,
                object: self,
                userInfo: [
                    OAuthNotificationKey.accountType: accountType,
                    OAuthNotificationKey.accountId: accountId,
                    OAuthNotificationKey.error: error
                ]
            )
        }
    }
    
    private func exchangeGoogleCode(code: String) async throws -> (accessToken: String, refreshToken: String, idToken: String?, email: String?) {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
            "client_secret": "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",
            "code": code,
            "redirect_uri": "http://127.0.0.1:12111/callback",
            "grant_type": "authorization_code"
        ]
        
        let bodyString = parameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OAuthServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Exchange failed"])
        }
        
        struct TokenResp: Codable {
            let access_token: String
            let refresh_token: String
            let id_token: String?
        }
        
        let decoded = try JSONDecoder().decode(TokenResp.self, from: data)
        let email = decoded.id_token.flatMap { SystemCredentialDetector.parseJWTClaim($0, claim: "email") }
        return (decoded.access_token, decoded.refresh_token, decoded.id_token, email)
    }
    
    private func exchangeCodexCode(code: String, verifier: String) async throws -> (accessToken: String, refreshToken: String, idToken: String?, accountId: String?, email: String?) {
        let url = URL(string: "https://auth.openai.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        
        let parameters = [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "http://127.0.0.1:12111/callback",
            "code_verifier": verifier
        ]
        
        let bodyString = parameters.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OAuthServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Exchange failed"])
        }
        
        struct TokenResp: Codable {
            let access_token: String
            let refresh_token: String
            let id_token: String?
        }
        
        let decoded = try JSONDecoder().decode(TokenResp.self, from: data)
        
        var accountId: String? = nil
        if let idToken = decoded.id_token {
            accountId = APIClient.ParseIDTokenUserID(idToken)
        }
        let email = decoded.id_token.flatMap { SystemCredentialDetector.parseJWTClaim($0, claim: "email") }
        
        return (decoded.access_token, decoded.refresh_token, decoded.id_token, accountId, email)
    }
    
    private func generatePKCEPair() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
            
        return (verifier, challenge)
    }
}
