import Foundation

/// `design/SERVER.md` §1.3 のトークン応答 `{ access_token, refresh_token, token_type, expires_in }`。
/// access token はメモリ保持 (呼び出し側責務)、refresh token のみ `TokenStore` で永続化する。
struct TokenCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

enum AuthRepositoryError: Error, Equatable {
    /// 保存済み refresh token が存在しないため refresh を開始できない。
    case missingRefreshToken
}

protocol AuthRepository {
    /// auth code と PKCE verifier を本トークンへ交換し、refresh token を保存する。
    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials

    /// 保存済み refresh token で access token を再発行し、rotation 済み refresh token で置き換える。
    @discardableResult
    func refreshTokens() async throws -> TokenCredentials

    /// 保存済み refresh token を server 側で失効させ、成功時にローカル credential を消去する。
    func revokeAndClearCredentials(accessToken: String) async throws
}

struct FeedmanAuthRepository: AuthRepository {
    let apiClient: APIClient
    let tokenStore: TokenStore

    @discardableResult
    func exchangeAuthCode(_ authCode: String, codeVerifier: String) async throws -> TokenCredentials {
        let credentials = try await apiClient.send(
            TokenCredentials.self,
            method: .post,
            path: "/api/auth/token",
            body: TokenExchangeRequestBody(authCode: authCode, codeVerifier: codeVerifier)
        )
        try tokenStore.saveRefreshToken(credentials.refreshToken)
        return credentials
    }

    @discardableResult
    func refreshTokens() async throws -> TokenCredentials {
        guard let storedToken = try tokenStore.loadRefreshToken() else {
            throw AuthRepositoryError.missingRefreshToken
        }

        let credentials = try await apiClient.send(
            TokenCredentials.self,
            method: .post,
            path: "/api/auth/refresh",
            body: RefreshTokenRequestBody(refreshToken: storedToken)
        )
        try tokenStore.saveRefreshToken(credentials.refreshToken)
        return credentials
    }

    func revokeAndClearCredentials(accessToken: String) async throws {
        guard let storedToken = try tokenStore.loadRefreshToken() else {
            // 失効対象がなければ冪等なログアウトとしてローカル消去のみ行う。
            try tokenStore.clearCredentials()
            return
        }

        try await apiClient.sendNoContent(
            method: .post,
            path: "/api/auth/revoke",
            body: RefreshTokenRequestBody(refreshToken: storedToken),
            accessToken: accessToken
        )
        try tokenStore.clearCredentials()
    }
}

private struct TokenExchangeRequestBody: Encodable {
    let authCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authCode = "auth_code"
        case codeVerifier = "code_verifier"
    }
}

private struct RefreshTokenRequestBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
