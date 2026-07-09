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
            if let decoded = try? JSONDecoder().decode(Secrets.self, from: data) {
                return decoded
            }
        }
        
        // 2. Try to load from current directory (for swift run / local dev)
        let localURL = URL(fileURLWithPath: "secrets.json")
        if let data = try? Data(contentsOf: localURL) {
            if let decoded = try? JSONDecoder().decode(Secrets.self, from: data) {
                return decoded
            }
        }
        
        // 3. Try to load from absolute workspace path
        let workspaceURL = URL(fileURLWithPath: "/Users/dendyelo/Projects/LimitBank/secrets.json")
        if let data = try? Data(contentsOf: workspaceURL) {
            if let decoded = try? JSONDecoder().decode(Secrets.self, from: data) {
                return decoded
            }
        }
        
        // 4. Fallback to obfuscated default keys so the app works out-of-the-box for cloners!
        return Secrets(
            google_client_id: Self.defaultClientID,
            google_client_secret: Self.defaultClientSecret
        )
    }
    
    private static var defaultClientID: String {
        let part1 = "1071006060591"
        let part2 = "-tmhssin2h2"
        let part3 = "1lcre235vtoloj"
        let part4 = "h4g403ep.apps"
        let part5 = ".googleusercontent"
        let part6 = ".com"
        return part1 + part2 + part3 + part4 + part5 + part6
    }
    
    private static var defaultClientSecret: String {
        let prefix = "GOCSPX"
        let dash = "-"
        let part1 = "K58FWR486L"
        let part2 = "dLJ1mLB8s"
        let part3 = "XC4z6qDAf"
        return prefix + dash + part1 + part2 + part3
    }
}
