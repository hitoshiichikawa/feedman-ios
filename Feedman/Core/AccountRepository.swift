import Foundation

protocol AccountRepository {
    func currentUser(accessToken: String) async throws -> UserResponse
}

struct FeedmanAccountRepository: AccountRepository {
    let apiClient: APIClient

    func currentUser(accessToken: String) async throws -> UserResponse {
        try await apiClient.send(
            UserResponse.self,
            path: "/auth/me",
            accessToken: accessToken
        )
    }
}

struct UnavailableAccountRepository: AccountRepository {
    func currentUser(accessToken: String) async throws -> UserResponse {
        throw AccountRepositoryError.authenticatedSessionUnavailable
    }
}

enum AccountRepositoryError: Error, Equatable {
    case authenticatedSessionUnavailable
}
