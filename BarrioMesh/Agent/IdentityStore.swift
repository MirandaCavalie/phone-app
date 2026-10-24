import Foundation
import Security

/// Keeps this phone's signing key in the Keychain, readable only on this device.
enum IdentityStore {
    private static let service = "com.faro.identity"
    private static let account = "signing-key"

    static func loadOrCreate() -> AgentIdentity {
        if let data = read(), let identity = try? AgentIdentity(rawRepresentation: data) {
            return identity
        }
        let identity = AgentIdentity()
        write(identity.privateKey.rawRepresentation)
        return identity
    }

    private static func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func write(_ data: Data) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(attributes as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
