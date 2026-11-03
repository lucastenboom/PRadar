import Foundation
import Security

struct KeychainTokenStore: Sendable {
    static let app = KeychainTokenStore(service: "io.github.lucastenboom.PRadar")

    private static let account = "github-token"

    let service: String

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func read() -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    func save(_ token: String) throws {
        delete()

        var query = itemQuery
        query[kSecValueData as String] = Data(token.utf8)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete() {
        SecItemDelete(itemQuery as CFDictionary)
    }
}
