import Foundation

protocol PasskeyRepository {
    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse
    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse
    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse
    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse
    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse
    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws
}

struct FeedmanPasskeyRepository: PasskeyRepository {
    let apiClient: APIClient

    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse {
        try await apiClient.send(
            PasskeyRegistrationBeginResponse.self,
            method: .post,
            path: "/api/passkey/registration/begin",
            body: PasskeyRegistrationBeginRequest(
                username: username,
                codeChallenge: codeChallenge
            )
        )
    }

    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        try await apiClient.send(
            PasskeyRegistrationFinishResponse.self,
            method: .post,
            path: "/api/passkey/registration/finish",
            body: PasskeyRegistrationFinishRequest(
                challengeID: challengeID,
                credential: credential
            )
        )
    }

    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse {
        try await apiClient.send(
            PasskeyAuthenticationBeginResponse.self,
            method: .post,
            path: "/api/passkey/authentication/begin",
            body: PasskeyAuthenticationBeginRequest(codeChallenge: codeChallenge)
        )
    }

    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        try await apiClient.send(
            PasskeyAuthenticationFinishResponse.self,
            method: .post,
            path: "/api/passkey/authentication/finish",
            body: PasskeyAuthenticationFinishRequest(
                challengeID: challengeID,
                credential: credential
            )
        )
    }

    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse {
        try await apiClient.send(
            PasskeyAddRegistrationBeginResponse.self,
            method: .post,
            path: "/api/passkey/registration/add/begin",
            body: PasskeyEmptyRequest(),
            accessToken: accessToken
        )
    }

    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws {
        try await apiClient.sendNoContent(
            method: .post,
            path: "/api/passkey/registration/add/finish",
            body: PasskeyAddRegistrationFinishRequest(
                challengeID: challengeID,
                credential: credential
            ),
            accessToken: accessToken
        )
    }
}

struct UnavailablePasskeyRepository: PasskeyRepository {
    func beginRegistration(
        username: String,
        codeChallenge: String
    ) async throws -> PasskeyRegistrationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyRegistrationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishAuthentication(
        challengeID: String,
        credential: PasskeyCredentialEnvelope
    ) async throws -> PasskeyAuthenticationFinishResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func beginAddRegistration(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse {
        throw PasskeyRepositoryError.unavailable
    }

    func finishAddRegistration(
        challengeID: String,
        credential: PasskeyCredentialEnvelope,
        accessToken: String
    ) async throws {
        throw PasskeyRepositoryError.unavailable
    }
}

enum PasskeyRepositoryError: Error, Equatable {
    case unavailable
}
