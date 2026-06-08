import Security
import XCTest
@testable import Feedman

final class TokenStoreTests: XCTestCase {
    func testLoadReturnsNilWhenRefreshTokenIsMissing() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        let token = try store.loadRefreshToken()

        XCTAssertNil(token)
    }

    func testSavePersistsRefreshTokenForLaterLoad() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        try store.saveRefreshToken("refresh-token")

        XCTAssertEqual(try store.loadRefreshToken(), "refresh-token")
    }

    func testSaveUsesAfterFirstUnlockAccessibility() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        try store.saveRefreshToken("refresh-token")

        let accessibility = keychain.lastAddQuery?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessibility, kSecAttrAccessibleAfterFirstUnlock as String)
    }

    func testSaveOverwritesExistingRefreshToken() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        try store.saveRefreshToken("old-token")
        try store.saveRefreshToken("new-token")

        XCTAssertEqual(try store.loadRefreshToken(), "new-token")
    }

    func testClearCredentialsRemovesRefreshToken() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        try store.saveRefreshToken("refresh-token")
        try store.clearCredentials()

        XCTAssertNil(try store.loadRefreshToken())
    }

    func testClearCredentialsSucceedsWhenTokenIsAlreadyMissing() throws {
        let keychain = FakeKeychainClient()
        let store = makeStore(keychain: keychain)

        try store.clearCredentials()

        XCTAssertNil(try store.loadRefreshToken())
    }

    func testSaveSurfacesTypedKeychainError() {
        let keychain = FakeKeychainClient()
        keychain.addStatusOverride = errSecInteractionNotAllowed
        let store = makeStore(keychain: keychain)

        assertThrows(
            try store.saveRefreshToken("refresh-token"),
            TokenStoreError.keychainError(operation: .add, status: errSecInteractionNotAllowed)
        )
    }

    func testLoadSurfacesTypedKeychainError() {
        let keychain = FakeKeychainClient()
        keychain.copyStatusOverride = errSecAuthFailed
        let store = makeStore(keychain: keychain)

        assertThrows(
            try store.loadRefreshToken(),
            TokenStoreError.keychainError(operation: .copyMatching, status: errSecAuthFailed)
        )
    }

    func testSaveSurfacesTypedUpdateErrorAfterDuplicateItem() {
        let keychain = FakeKeychainClient()
        keychain.storedData = Data("old-token".utf8)
        keychain.updateStatusOverride = errSecInteractionNotAllowed
        let store = makeStore(keychain: keychain)

        assertThrows(
            try store.saveRefreshToken("new-token"),
            TokenStoreError.keychainError(operation: .update, status: errSecInteractionNotAllowed)
        )
    }

    func testClearSurfacesTypedKeychainError() {
        let keychain = FakeKeychainClient()
        keychain.deleteStatusOverride = errSecAuthFailed
        let store = makeStore(keychain: keychain)

        assertThrows(
            try store.clearCredentials(),
            TokenStoreError.keychainError(operation: .delete, status: errSecAuthFailed)
        )
    }

    func testLoadRejectsInvalidUTF8StoredData() {
        let keychain = FakeKeychainClient()
        keychain.storedData = Data([0xFF])
        let store = makeStore(keychain: keychain)

        assertThrows(try store.loadRefreshToken(), TokenStoreError.invalidStoredData)
    }

    private func makeStore(keychain: FakeKeychainClient) -> KeychainTokenStore {
        KeychainTokenStore(
            service: "com.hitoshiichikawa.feedman.tests.auth.refresh-token",
            account: "refresh_token",
            keychain: keychain
        )
    }

    private func assertThrows<T, ExpectedError: Error & Equatable>(
        _ expression: @autoclosure () throws -> T,
        _ expectedError: ExpectedError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch let error as ExpectedError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private final class FakeKeychainClient: KeychainClient {
    var storedData: Data?
    var addStatusOverride: OSStatus?
    var updateStatusOverride: OSStatus?
    var copyStatusOverride: OSStatus?
    var deleteStatusOverride: OSStatus?
    var lastAddQuery: [String: Any]?

    func add(_ query: [String: Any]) -> OSStatus {
        lastAddQuery = query

        if let addStatusOverride {
            return addStatusOverride
        }

        guard storedData == nil else {
            return errSecDuplicateItem
        }

        storedData = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if let updateStatusOverride {
            return updateStatusOverride
        }

        guard storedData != nil else {
            return errSecItemNotFound
        }

        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        if let copyStatusOverride {
            return copyStatusOverride
        }

        guard let storedData else {
            return errSecItemNotFound
        }

        result?.pointee = storedData as NSData
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if let deleteStatusOverride {
            return deleteStatusOverride
        }

        guard storedData != nil else {
            return errSecItemNotFound
        }

        storedData = nil
        return errSecSuccess
    }
}
