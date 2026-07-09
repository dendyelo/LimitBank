import Foundation

public struct Secrets: Codable {
    public let google_client_id: String
    public let google_client_secret: String
}

public class SecretsManager {
    public static let shared = SecretsManager()
    
    public var secrets: Secrets?
    
    private init() {
        self.secrets = loadSecrets()
    }
    
    private func loadSecrets() -> Secrets? {
        // 1. Try to load from Bundle Resources (when running inside LimitBank.app bundle)
        if let path = Bundle.main.path(forResource: "secrets", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        
        // 2. Try to load from current directory (for swift run / local dev)
        let localURL = URL(fileURLWithPath: "secrets.json")
        if let data = try? Data(contentsOf: localURL) {
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        
        // 3. Try to load from absolute workspace path
        let workspaceURL = URL(fileURLWithPath: "/Users/dendyelo/Projects/LimitBank/secrets.json")
        if let data = try? Data(contentsOf: workspaceURL) {
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        
        return nil
    }
}
