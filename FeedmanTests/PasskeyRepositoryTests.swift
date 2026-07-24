import XCTest
@testable import Feedman

final class PasskeyRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testBeginRegistrationPostsUsernameAndCodeChallengeOnly() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: registrationBeginData(), statusCode: 200)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let response = try await repository.beginRegistration(
            username: "reader",
            codeChallenge: "challenge-s256"
        )

        XCTAssertEqual(response.challengeID, "registration-challenge")
        XCTAssertEqual(response.options.publicKey.rp.id, "feedman.example.com")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/registration/begin")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try jsonObject(request.httpBody)
        XCTAssertEqual(body["username"] as? String, "reader")
        XCTAssertEqual(body["code_challenge"] as? String, "challenge-s256")
        XCTAssertNil(body["email"])
        XCTAssertNil(body["credential_id"])
    }

    func testFinishRegistrationPostsChallengeAndCredentialAndDecodesUserIDOnly() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: Data(#"{"user_id":"user-1"}"#.utf8), statusCode: 200)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let response = try await repository.finishRegistration(
            challengeID: "registration-challenge",
            credential: registrationCredential()
        )

        XCTAssertEqual(response.userID, "user-1")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/registration/finish")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try jsonObject(request.httpBody)
        XCTAssertEqual(body["challenge_id"] as? String, "registration-challenge")
        let credential = try XCTUnwrap(body["credential"] as? [String: Any])
        XCTAssertEqual(credential["id"] as? String, "credential-id")
        XCTAssertEqual(credential["rawId"] as? String, "credential-raw-id")
        XCTAssertEqual(credential["type"] as? String, "public-key")
        XCTAssertNil(body["auth_code"])
    }

    func testBeginAuthenticationPostsCodeChallengeOnly() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: authenticationBeginData(), statusCode: 200)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let response = try await repository.beginAuthentication(codeChallenge: "challenge-s256")

        XCTAssertEqual(response.challengeID, "authentication-challenge")
        XCTAssertEqual(response.options.publicKey.rpID, "feedman.example.com")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/authentication/begin")
        let body = try jsonObject(request.httpBody)
        XCTAssertEqual(body["code_challenge"] as? String, "challenge-s256")
        XCTAssertNil(body["credential_id"])
        XCTAssertNil(body["allow_credentials"])
    }

    func testFinishAuthenticationPostsCredentialAndDecodesAuthCode() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: Data(#"{"auth_code":"native-auth-code"}"#.utf8), statusCode: 200)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let response = try await repository.finishAuthentication(
            challengeID: "authentication-challenge",
            credential: assertionCredential()
        )

        XCTAssertEqual(response.authCode, "native-auth-code")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/authentication/finish")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try jsonObject(request.httpBody)
        XCTAssertEqual(body["challenge_id"] as? String, "authentication-challenge")
        let credential = try XCTUnwrap(body["credential"] as? [String: Any])
        let credentialResponse = try XCTUnwrap(credential["response"] as? [String: Any])
        XCTAssertEqual(credentialResponse["authenticatorData"] as? String, "authenticator-data")
        XCTAssertEqual(credentialResponse["signature"] as? String, "signature")
    }

    func testBeginAddRegistrationUsesBearerTokenAndEmptyJSONBody() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: registrationBeginData(challengeID: "add-challenge"), statusCode: 200)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let response = try await repository.beginAddRegistration(accessToken: "access-1")

        XCTAssertEqual(response.challengeID, "add-challenge")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/registration/add/begin")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(try jsonObject(request.httpBody).isEmpty)
    }

    func testFinishAddRegistrationUsesBearerTokenAndAcceptsNoContent() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        try await repository.finishAddRegistration(
            challengeID: "add-challenge",
            credential: registrationCredential(),
            accessToken: "access-1"
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/passkey/registration/add/finish")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let body = try jsonObject(request.httpBody)
        XCTAssertEqual(body["challenge_id"] as? String, "add-challenge")
    }

    func testAddRegistrationDelegatesExpiredTokenRefreshToAPIClient() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), statusCode: 401)
        transport.enqueue(data: Data(), statusCode: 204)
        let refreshHook = PasskeyRefreshHook(accessToken: "access-2")
        let repository = FeedmanPasskeyRepository(
            apiClient: APIClient(
                baseURL: baseURL,
                transport: transport,
                accessTokenRefreshHook: {
                    await refreshHook.refresh()
                }
            )
        )

        try await repository.finishAddRegistration(
            challengeID: "add-challenge",
            credential: registrationCredential(),
            accessToken: "access-1"
        )

        let refreshCount = await refreshHook.callCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer access-1",
            "Bearer access-2"
        ])
    }

    func testRepositoryPropagatesServerErrors() async throws {
        let transport = PasskeyRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "USERNAME_TAKEN"), statusCode: 409)
        let repository = FeedmanPasskeyRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        do {
            _ = try await repository.beginRegistration(username: "reader", codeChallenge: "challenge-s256")
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 409)
            XCTAssertEqual(context.code, "USERNAME_TAKEN")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOptionsPublicKeyMissingFailsDecode() throws {
        let data = Data(#"{"challenge_id":"challenge","options":{}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(PasskeyAuthenticationBeginResponse.self, from: data))
    }

    func testUserResponseDecodesOptionalUsername() throws {
        let data = Data(
            #"{"id":"user-1","username":"reader","email":null,"name":null,"avatar_url":null}"#.utf8
        )

        let response = try JSONDecoder().decode(UserResponse.self, from: data)

        XCTAssertEqual(response.username, "reader")
        XCTAssertNil(response.email)
        XCTAssertNil(response.name)
    }

    func testCredentialEnvelopePreservesBase64URLFields() throws {
        let credential = registrationCredential()

        let data = try JSONEncoder().encode(credential)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["rawId"] as? String, "credential-raw-id")
        let response = try XCTUnwrap(object["response"] as? [String: Any])
        XCTAssertEqual(response["clientDataJSON"] as? String, "client-data-json")
        XCTAssertEqual(response["attestationObject"] as? String, "attestation-object")
    }
}

private func registrationCredential() -> PasskeyCredentialEnvelope {
    PasskeyCredentialEnvelope(
        id: "credential-id",
        rawID: "credential-raw-id",
        type: "public-key",
        response: .registration(
            PasskeyRegistrationCredentialResponse(
                clientDataJSON: "client-data-json",
                attestationObject: "attestation-object",
                transports: ["internal"]
            )
        )
    )
}

private func assertionCredential() -> PasskeyCredentialEnvelope {
    PasskeyCredentialEnvelope(
        id: "credential-id",
        rawID: "credential-raw-id",
        type: "public-key",
        response: .assertion(
            PasskeyAssertionCredentialResponse(
                clientDataJSON: "client-data-json",
                authenticatorData: "authenticator-data",
                signature: "signature",
                userHandle: nil
            )
        )
    )
}

private func registrationBeginData(challengeID: String = "registration-challenge") -> Data {
    Data(
        """
        {
          "challenge_id": "\(challengeID)",
          "options": {
            "publicKey": {
              "challenge": "server-challenge",
              "rp": {
                "id": "feedman.example.com",
                "name": "Feedman"
              },
              "user": {
                "id": "user-handle",
                "name": "reader",
                "displayName": "reader"
              },
              "pubKeyCredParams": [
                { "type": "public-key", "alg": -7 }
              ],
              "timeout": 60000,
              "excludeCredentials": [
                { "type": "public-key", "id": "existing-credential" }
              ],
              "authenticatorSelection": {
                "authenticatorAttachment": "platform",
                "residentKey": "required",
                "userVerification": "required"
              },
              "attestation": "none"
            }
          }
        }
        """.utf8
    )
}

private func authenticationBeginData() -> Data {
    Data(
        """
        {
          "challenge_id": "authentication-challenge",
          "options": {
            "publicKey": {
              "challenge": "server-challenge",
              "rpId": "feedman.example.com",
              "timeout": 60000,
              "allowCredentials": [
                { "type": "public-key", "id": "allowed-credential" }
              ],
              "userVerification": "required"
            }
          }
        }
        """.utf8
    )
}

private func jsonObject(_ body: Data?) throws -> [String: Any] {
    let body = try XCTUnwrap(body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func feedmanErrorData(code: String) -> Data {
    Data(
        """
        {
          "error": {
            "code": "\(code)",
            "message": "Passkey request failed.",
            "category": "validation",
            "action": "retry"
          }
        }
        """.utf8
    )
}

private final class PasskeyRecordingTransport: APITransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var queuedResults: [(Data, Int)] = []

    func enqueue(data: Data, statusCode: Int) {
        queuedResults.append((data, statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queuedResults.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let (data, statusCode) = queuedResults.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor PasskeyRefreshHook {
    private let accessToken: String
    private(set) var callCount = 0

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func refresh() -> String {
        callCount += 1
        return accessToken
    }
}
