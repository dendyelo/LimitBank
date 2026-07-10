import Foundation
import XCTest
@testable import LimitBank

final class ConfigTests: XCTestCase {
    func testCodexAuthFileUsesChatGPTSessionSchema() throws {
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory
            .appendingPathComponent("LimitBankTests-\(UUID().uuidString)", isDirectory: true)
        let previousCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]

        setenv("CODEX_HOME", temporaryHome.path, 1)
        defer {
            if let previousCodexHome {
                setenv("CODEX_HOME", previousCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
            try? fileManager.removeItem(at: temporaryHome)
        }

        let account = AccountConfig(
            type: "codex",
            label: "Test Codex",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token",
            accountId: "account-id"
        )

        try SystemCredentialDetector.writeCodexAuthFile(for: account)

        let authURL = temporaryHome.appendingPathComponent("auth.json")
        let data = try Data(contentsOf: authURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tokens = try XCTUnwrap(root["tokens"] as? [String: Any])

        XCTAssertEqual(root["auth_mode"] as? String, "chatgpt")
        XCTAssertTrue(root["OPENAI_API_KEY"] is NSNull)
        XCTAssertNotNil(root["last_refresh"] as? String)
        XCTAssertEqual(tokens["access_token"] as? String, "access-token")
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-token")
        XCTAssertEqual(tokens["id_token"] as? String, "id-token")
        XCTAssertEqual(tokens["account_id"] as? String, "account-id")

        let detected = try XCTUnwrap(SystemCredentialDetector.detectCodex(includeOpenCodeFallback: false))
        XCTAssertEqual(detected.accessToken, "access-token")
        XCTAssertEqual(detected.refreshToken, "refresh-token")
        XCTAssertEqual(detected.idToken, "id-token")
        XCTAssertEqual(detected.accountId, "account-id")
    }
}
