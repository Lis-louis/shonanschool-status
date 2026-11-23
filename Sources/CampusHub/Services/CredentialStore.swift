import Foundation
import Security

struct Credentials: Codable, Sendable, Equatable {
    var username: String
    var password: String
}

/// ID・パスワードを macOS キーチェーンに保存する。
/// - このMacのロック解除中だけ読める（`WhenUnlockedThisDeviceOnly`：iCloud同期・バックアップ移行されない）
/// - 画面やログには出さない。使うのは公式ログインページの入力欄へ入れるときだけ
enum CredentialStore {
    private static let service = "local.campushub.credentials"

    private static func query(_ s: PortalService) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: s.rawValue]
    }

    @discardableResult
    static func save(_ c: Credentials, for s: PortalService) -> Bool {
        guard let data = try? JSONEncoder().encode(c) else { return false }
        delete(s)
        var q = query(s)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        q[kSecAttrLabel as String] = "キャンパスハブ（\(s.label)）"
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ s: PortalService) -> Credentials? {
        var q = query(s)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete(_ s: PortalService) {
        SecItemDelete(query(s) as CFDictionary)
    }
}
