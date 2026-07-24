import AuthenticationServices
import XCTest
@testable import Feedman

@MainActor
final class PasskeyPlatformAuthorizationCoordinatorTests: XCTestCase {
    func testRegistrationRequestDecodesChallengeUserIDAndKeepsRelyingPartyString() throws {
        let coordinator = makeCoordinator()

        let request = try coordinator.makeRegistrationRequest(options: registrationOptions())

        XCTAssertEqual(request.kind, .registration)
        XCTAssertEqual(request.relyingPartyID, "feedman.example.com")
        XCTAssertEqual(request.challenge, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(request.userID, Data([0x04, 0x05, 0x06]))
        XCTAssertEqual(request.userName, "reader")
        XCTAssertEqual(request.displayName, "Reader")
        XCTAssertEqual(request.userVerification, "required")
        XCTAssertEqual(request.excludedCredentialIDs, [Data([0x07, 0x08, 0x09])])
        XCTAssertEqual(request.exclusionHandling, .unsupportedByIOS16Minimum)
    }

    func testRegistrationRequestFailsWhenRequiredBase64URLFieldIsInvalid() throws {
        let coordinator = makeCoordinator()
        let options = registrationOptions(challenge: "not valid base64url!")

        XCTAssertThrowsError(try coordinator.makeRegistrationRequest(options: options)) { error in
            XCTAssertEqual(
                error as? PasskeyPlatformAuthorizationError,
                .invalidOptions("challenge")
            )
        }
    }

    func testRegistrationRequestFailsWhenRelyingPartyIDIsMissing() throws {
        let coordinator = makeCoordinator()
        let options = registrationOptions(relyingPartyID: nil)

        XCTAssertThrowsError(try coordinator.makeRegistrationRequest(options: options)) { error in
            XCTAssertEqual(
                error as? PasskeyPlatformAuthorizationError,
                .invalidOptions("rp.id")
            )
        }
    }

    func testAssertionRequestUsesOptionsAllowCredentialsForDiscoverableLogin() throws {
        let coordinator = makeCoordinator()

        let request = try coordinator.makeAssertionRequest(options: assertionOptions())

        XCTAssertEqual(request.kind, .assertion)
        XCTAssertEqual(request.relyingPartyID, "feedman.example.com")
        XCTAssertEqual(request.challenge, Data([0x0A, 0x0B, 0x0C]))
        XCTAssertEqual(request.allowedCredentialIDs, [Data([0x0D, 0x0E, 0x0F])])
        XCTAssertEqual(request.userVerification, "preferred")
        XCTAssertNil(request.userID)
    }

    func testAssertionRequestUsesLocalAllowedCredentialOverrideForSignupHandoff() throws {
        let coordinator = makeCoordinator()

        let request = try coordinator.makeAssertionRequest(
            options: assertionOptions(allowedCredentialID: "ignored-server-id"),
            allowedCredentialID: "EAEC"
        )

        XCTAssertEqual(request.allowedCredentialIDs, [Data([0x10, 0x01, 0x02])])
    }

    func testRegistrationCredentialConvertsToWebAuthnEnvelope() async throws {
        let performer = RecordingPasskeyAuthorizationPerformer(result: .registration(PasskeyPlatformRegistrationCredential(
            credentialID: Data([0x01, 0x02, 0x03]),
            clientDataJSON: Data(#"{"type":"webauthn.create"}"#.utf8),
            attestationObject: Data([0x04, 0x05, 0x06])
        )))
        let coordinator = makeCoordinator(performer: performer)

        let envelope = try await coordinator.performRegistration(options: registrationOptions())

        XCTAssertEqual(envelope.id, "AQID")
        XCTAssertEqual(envelope.rawID, "AQID")
        XCTAssertEqual(envelope.type, "public-key")
        guard case .registration(let response) = envelope.response else {
            return XCTFail("Expected registration response")
        }
        XCTAssertEqual(response.clientDataJSON, "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIn0")
        XCTAssertEqual(response.attestationObject, "BAUG")
    }

    func testAssertionCredentialConvertsToWebAuthnEnvelope() async throws {
        let performer = RecordingPasskeyAuthorizationPerformer(result: .assertion(PasskeyPlatformAssertionCredential(
            credentialID: Data([0x0D, 0x0E, 0x0F]),
            clientDataJSON: Data(#"{"type":"webauthn.get"}"#.utf8),
            authenticatorData: Data([0x01, 0x02]),
            signature: Data([0x03, 0x04]),
            userID: Data([0x05, 0x06])
        )))
        let coordinator = makeCoordinator(performer: performer)

        let envelope = try await coordinator.performAssertion(options: assertionOptions())

        XCTAssertEqual(envelope.id, "DQ4P")
        guard case .assertion(let response) = envelope.response else {
            return XCTFail("Expected assertion response")
        }
        XCTAssertEqual(response.clientDataJSON, "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0In0")
        XCTAssertEqual(response.authenticatorData, "AQI")
        XCTAssertEqual(response.signature, "AwQ")
        XCTAssertEqual(response.userHandle, "BQY")
    }

    func testPresentationAnchorUnavailableFailsBeforeStartingPlatformAuthorization() async {
        let performer = RecordingPasskeyAuthorizationPerformer(result: .assertion(PasskeyPlatformAssertionCredential(
            credentialID: Data(),
            clientDataJSON: Data(),
            authenticatorData: Data(),
            signature: Data(),
            userID: Data()
        )))
        let coordinator = makeCoordinator(performer: performer, hasPresentationAnchor: false)

        do {
            _ = try await coordinator.performAssertion(options: assertionOptions())
            XCTFail("Expected presentation anchor error")
        } catch {
            XCTAssertEqual(error as? PasskeyPlatformAuthorizationError, .presentationAnchorUnavailable)
            XCTAssertEqual(performer.performCallCount, 0)
        }
    }

    func testDuplicateAttemptIsRejectedAndActiveAttemptIsReleasedAfterCompletion() async throws {
        let performer = SuspendedPasskeyAuthorizationPerformer()
        let coordinator = makeCoordinator(performer: performer)
        let firstAttempt = Task {
            try await coordinator.performAssertion(options: assertionOptions())
        }
        await performer.waitUntilStarted()

        do {
            _ = try await coordinator.performAssertion(options: assertionOptions())
            XCTFail("Expected duplicate attempt rejection")
        } catch {
            XCTAssertEqual(error as? PasskeyPlatformAuthorizationError, .authorizationAlreadyActive)
        }

        performer.succeed(with: .assertion(PasskeyPlatformAssertionCredential(
            credentialID: Data([0x01]),
            clientDataJSON: Data([0x02]),
            authenticatorData: Data([0x03]),
            signature: Data([0x04]),
            userID: Data([0x05])
        )))
        _ = try await firstAttempt.value

        let secondAttempt = Task {
            try await coordinator.performAssertion(options: assertionOptions())
        }
        await performer.waitUntilStarted(callCount: 2)
        XCTAssertEqual(performer.performCallCount, 2)
        secondAttempt.cancel()
        _ = try? await secondAttempt.value
    }

    func testTaskCancellationPropagatesCancelAndMapsToCanceledExactlyOnce() async {
        let performer = SuspendedPasskeyAuthorizationPerformer()
        let coordinator = makeCoordinator(performer: performer)
        let task = Task {
            try await coordinator.performAssertion(options: assertionOptions())
        }
        await performer.waitUntilStarted()

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected canceled error")
        } catch {
            XCTAssertEqual(error as? PasskeyPlatformAuthorizationError, .canceled)
        }
        XCTAssertEqual(performer.cancelCallCount, 1)
        XCTAssertEqual(performer.resumeCount, 1)
    }

    func testPlatformCancellationMapsSeparatelyFromFailure() async {
        let performer = RecordingPasskeyAuthorizationPerformer(error: PasskeyPlatformAuthorizationError.canceled)
        let coordinator = makeCoordinator(performer: performer)

        do {
            _ = try await coordinator.performAssertion(options: assertionOptions())
            XCTFail("Expected canceled error")
        } catch {
            XCTAssertEqual(error as? PasskeyPlatformAuthorizationError, .canceled)
        }
    }

    private func makeCoordinator(
        performer: (any PasskeyPlatformAuthorizationRequestPerforming)? = nil,
        hasPresentationAnchor: Bool = true
    ) -> PasskeyPlatformAuthorizationCoordinator {
        PasskeyPlatformAuthorizationCoordinator(
            authorizationPerformer: performer ?? RecordingPasskeyAuthorizationPerformer(),
            presentationAnchorProvider: { hasPresentationAnchor ? ASPresentationAnchor() : nil }
        )
    }
}

private func registrationOptions(
    challenge: String = "AQID",
    relyingPartyID: String? = "feedman.example.com"
) -> PasskeyPublicKeyCredentialCreationOptions {
    PasskeyPublicKeyCredentialCreationOptions(
        challenge: challenge,
        rp: PasskeyRelyingParty(id: relyingPartyID, name: "Feedman"),
        user: PasskeyUserEntity(id: "BAUG", name: "reader", displayName: "Reader"),
        pubKeyCredParams: [
            PasskeyPublicKeyCredentialParameter(type: "public-key", alg: -7)
        ],
        timeout: 60000,
        excludeCredentials: [
            PasskeyCredentialDescriptor(type: "public-key", id: "BwgJ")
        ],
        authenticatorSelection: PasskeyAuthenticatorSelectionCriteria(
            authenticatorAttachment: "platform",
            residentKey: "required",
            userVerification: "required"
        ),
        attestation: "none"
    )
}

private func assertionOptions(
    allowedCredentialID: String = "DQ4P"
) -> PasskeyPublicKeyCredentialRequestOptions {
    PasskeyPublicKeyCredentialRequestOptions(
        challenge: "CgsM",
        rpID: "feedman.example.com",
        timeout: 60000,
        allowCredentials: [
            PasskeyCredentialDescriptor(type: "public-key", id: allowedCredentialID)
        ],
        userVerification: "preferred"
    )
}

@MainActor
private final class RecordingPasskeyAuthorizationPerformer: PasskeyPlatformAuthorizationRequestPerforming {
    private(set) var performCallCount = 0
    private let result: PasskeyPlatformCredentialResult
    private let error: Error?

    init(
        result: PasskeyPlatformCredentialResult = .assertion(PasskeyPlatformAssertionCredential(
            credentialID: Data([0x01]),
            clientDataJSON: Data([0x02]),
            authenticatorData: Data([0x03]),
            signature: Data([0x04]),
            userID: Data([0x05])
        )),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult {
        performCallCount += 1
        if let error {
            throw error
        }
        return result
    }

    func cancel() {}
}

@MainActor
private final class SuspendedPasskeyAuthorizationPerformer: PasskeyPlatformAuthorizationRequestPerforming {
    private(set) var performCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var resumeCount = 0
    private var continuation: CheckedContinuation<PasskeyPlatformCredentialResult, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult {
        performCallCount += 1
        startedContinuation?.resume()
        startedContinuation = nil
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        cancelCallCount += 1
        resume(throwing: PasskeyPlatformAuthorizationError.canceled)
    }

    func waitUntilStarted(callCount: Int = 1) async {
        if performCallCount >= callCount {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func succeed(with result: PasskeyPlatformCredentialResult) {
        resume(returning: result)
    }

    private func resume(returning result: PasskeyPlatformCredentialResult) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        resumeCount += 1
        continuation.resume(returning: result)
    }

    private func resume(throwing error: Error) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        resumeCount += 1
        continuation.resume(throwing: error)
    }
}
