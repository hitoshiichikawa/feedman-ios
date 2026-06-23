import Foundation

protocol AccountRepository {
    func currentUser(accessToken: String) async throws -> UserResponse
    func deleteCurrentUser(accessToken: String) async throws
}

struct FeedmanAccountRepository: AccountRepository {
    let apiClient: APIClient

    func currentUser(accessToken: String) async throws -> UserResponse {
        try await apiClient.send(
            UserResponse.self,
            path: "/api/users/me",
            accessToken: accessToken
        )
    }

    func deleteCurrentUser(accessToken: String) async throws {
        try await apiClient.sendNoContent(
            method: .delete,
            path: "/api/users/me",
            accessToken: accessToken
        )
    }
}

struct UnavailableAccountRepository: AccountRepository {
    func currentUser(accessToken: String) async throws -> UserResponse {
        throw AccountRepositoryError.authenticatedSessionUnavailable
    }

    func deleteCurrentUser(accessToken: String) async throws {
        throw AccountRepositoryError.authenticatedSessionUnavailable
    }
}

enum AccountRepositoryError: Error, Equatable {
    case authenticatedSessionUnavailable
}
