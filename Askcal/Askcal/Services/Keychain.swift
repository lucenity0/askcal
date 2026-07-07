//
//  Keychain.swift
//  Askcal
//
//  Minimal keychain wrapper — the refresh token never touches UserDefaults.
//

import Foundation
import Security

enum Keychain {
    private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.lucenity.askcal",
            kSecAttrAccount as String: key,
        ]
    }

    static func save(_ key: String, _ value: String) {
        var q = query(for: key)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
}
