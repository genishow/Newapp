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
    private let service: String
    private let account: String

    init(service: String = "com.geni.kinbir", account: String = "access_code") {
        self.service = service
        self.account = account
    }

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

/// A random ID for this phone, kept in the keychain so it survives deleting and
/// reinstalling the app. Sent with requests so the free gifts go to one person once,
/// not to every new email address on the same phone (D-456). Nothing else uses it.
enum DeviceID {
    static let value: String = {
        #if canImport(Security)
        let store = KeychainCodeStore(service: "com.geni.kinbir.device", account: "device-id")
        if let saved = store.load(), !saved.isEmpty { return saved }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        store.save(fresh)
        return fresh
        #else
        return ""
        #endif
    }()
}

