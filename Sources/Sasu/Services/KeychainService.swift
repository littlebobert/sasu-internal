import Foundation
import Security

struct KeychainService {
    private let service = "dev.sasu.Sasu"
    private let apiKeyAccount = "OpenAIAPIKey"
    private let backendAccessTokenAccount = "BackendAccessToken"

    func hasAPIKey() -> Bool {
        (try? readAPIKey()) != nil
    }

    func readAPIKey() throws -> String? {
        try readSecret(account: apiKeyAccount)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try saveSecret(apiKey, account: apiKeyAccount)
    }

    func deleteAPIKey() throws {
        try deleteSecret(account: apiKeyAccount)
    }

    func hasBackendAccessToken() -> Bool {
        (try? readBackendAccessToken()) != nil
    }

    func readBackendAccessToken() throws -> String? {
        try readSecret(account: backendAccessTokenAccount)
    }

    func saveBackendAccessToken(_ token: String) throws {
        try saveSecret(token, account: backendAccessTokenAccount)
    }

    func deleteBackendAccessToken() throws {
        try deleteSecret(account: backendAccessTokenAccount)
    }

    private func readSecret(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return secret
    }

    private func saveSecret(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    private func deleteSecret(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The saved API key could not be read."
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}
