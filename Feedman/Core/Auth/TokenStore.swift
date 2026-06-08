import Foundation
import Security

protocol TokenStore {
    func saveRefreshToken(_ token: String) throws
    func loadRefreshToken() throws -> String?
    func clearCredentials() throws
}

enum KeychainOperation: String, Equatable {
    case add
    case update
    case copyMatching
    case delete
}

enum TokenStoreError: Error, Equatable {
    case keychainError(operation: KeychainOperation, status: OSStatus)
    case invalidStoredData
}

protocol KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, result)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String
    private let keychain: KeychainClient

    init(
        service: String = KeychainTokenStore.defaultService,
        account: String = "refresh_token",
        keychain: KeychainClient = SystemKeychainClient()
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    func saveRefreshToken(_ token: String) throws {
        let tokenData = Data(token.utf8)
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = tokenData

        let addStatus = keychain.add(query)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try updateRefreshTokenData(tokenData)
        default:
            throw TokenStoreError.keychainError(operation: .add, status: addStatus)
        }
    }

    func loadRefreshToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = keychain.copyMatching(query, result: &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.invalidStoredData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychainError(operation: .copyMatching, status: status)
        }
    }

    func clearCredentials() throws {
        let status = keychain.delete(baseQuery())

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw TokenStoreError.keychainError(operation: .delete, status: status)
        }
    }

    private func updateRefreshTokenData(_ tokenData: Data) throws {
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: tokenData
        ]

        let status = keychain.update(baseQuery(), attributes: attributes)

        guard status == errSecSuccess else {
            throw TokenStoreError.keychainError(operation: .update, status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static var defaultService: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.hitoshiichikawa.feedman"
        return "\(bundleIdentifier).auth.refresh-token"
    }
}
