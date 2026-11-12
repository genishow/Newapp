import Foundation
import Security

/// Where the access code is kept. The real app uses the Keychain; tests use memory.
protocol CodeStore: AnyObject {
    func load() -> String?
    func save(_ code: String)
    func clear()
}

final class MemoryCodeStore: CodeStore {
    private var code: String?
    init(code: String? = nil) { self.code = code }
    func load() -> String? { code }
    func save(_ code: String) { self.code = code }
    func clear() { code = nil }
}

final class KeychainCodeStore: CodeStore {
    private let service = "com.geni.kinbir"
    private let account = "access_code"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let code = String(data: data, encoding: .utf8), !code.isEmpty else { return nil }
        return code
    }

    func save(_ code: String) {
        clear()
        var query = baseQuery
        query[kSecValueData as String] = Data(code.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
