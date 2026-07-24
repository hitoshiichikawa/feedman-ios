import AuthenticationServices
import Foundation
import UIKit

enum PasskeyPlatformAuthorizationError: Error, Equatable {
    case authorizationAlreadyActive
    case canceled
    case presentationAnchorUnavailable
    case invalidOptions(String)
    case invalidCredentialType
    case authorizationFailed
}

enum PasskeyPlatformAuthorizationKind: Equatable {
    case registration
    case assertion
}

enum PasskeyCredentialExclusionHandling: Equatable {
    case unsupportedByIOS16Minimum
}

struct PasskeyPlatformAuthorizationRequest: Equatable {
    let kind: PasskeyPlatformAuthorizationKind
    let relyingPartyID: String
    let challenge: Data
    let userName: String?
    let displayName: String?
    let userID: Data?
    let allowedCredentialIDs: [Data]
    let excludedCredentialIDs: [Data]
    let userVerification: String?
    let attestation: String?
    let exclusionHandling: PasskeyCredentialExclusionHandling
}

struct PasskeyPlatformRegistrationCredential: Equatable {
    let credentialID: Data
    let clientDataJSON: Data
    let attestationObject: Data?
}

struct PasskeyPlatformAssertionCredential: Equatable {
    let credentialID: Data
    let clientDataJSON: Data
    let authenticatorData: Data
    let signature: Data
    let userID: Data
}

enum PasskeyPlatformCredentialResult: Equatable {
    case registration(PasskeyPlatformRegistrationCredential)
    case assertion(PasskeyPlatformAssertionCredential)
}

@MainActor
protocol PasskeyPlatformAuthorizationRequestPerforming: AnyObject {
    func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult
    func cancel()
}

@MainActor
protocol PasskeyPlatformAuthorizationCoordinating {
    func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope
    func performAssertion(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String?
    ) async throws -> PasskeyCredentialEnvelope
    func cancelActiveAuthorization()
}

@MainActor
final class PasskeyPlatformAuthorizationCoordinator: PasskeyPlatformAuthorizationCoordinating {
    private let authorizationPerformer: any PasskeyPlatformAuthorizationRequestPerforming
    private let presentationAnchorProvider: () -> ASPresentationAnchor?
    private var activeAttempt: PasskeyPlatformAuthorizationAttempt?

    init(
        authorizationPerformer: (any PasskeyPlatformAuthorizationRequestPerforming)? = nil,
        presentationAnchorProvider: (() -> ASPresentationAnchor?)? = nil
    ) {
        let resolvedPresentationAnchorProvider = presentationAnchorProvider ?? Self.defaultPresentationAnchor
        self.authorizationPerformer = authorizationPerformer ?? ASPasskeyPlatformAuthorizationPerformer(
            presentationAnchorProvider: resolvedPresentationAnchorProvider
        )
        self.presentationAnchorProvider = resolvedPresentationAnchorProvider
    }

    func performRegistration(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) async throws -> PasskeyCredentialEnvelope {
        let request = try makeRegistrationRequest(options: options)
        let result = try await perform(request)
        guard case .registration(let credential) = result else {
            throw PasskeyPlatformAuthorizationError.invalidCredentialType
        }
        return PasskeyCredentialEnvelope(registrationCredential: credential)
    }

    func performAssertion(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String? = nil
    ) async throws -> PasskeyCredentialEnvelope {
        let request = try makeAssertionRequest(options: options, allowedCredentialID: allowedCredentialID)
        let result = try await perform(request)
        guard case .assertion(let credential) = result else {
            throw PasskeyPlatformAuthorizationError.invalidCredentialType
        }
        return PasskeyCredentialEnvelope(assertionCredential: credential)
    }

    func cancelActiveAuthorization() {
        activeAttempt?.cancel()
    }

    func makeRegistrationRequest(
        options: PasskeyPublicKeyCredentialCreationOptions
    ) throws -> PasskeyPlatformAuthorizationRequest {
        guard let relyingPartyID = nonEmpty(options.rp.id) else {
            throw PasskeyPlatformAuthorizationError.invalidOptions("rp.id")
        }

        let excludedCredentialIDs = try (options.excludeCredentials ?? []).map {
            try Self.decodeBase64URL($0.id, fieldName: "excludeCredentials.id")
        }

        return PasskeyPlatformAuthorizationRequest(
            kind: .registration,
            relyingPartyID: relyingPartyID,
            challenge: try Self.decodeBase64URL(options.challenge, fieldName: "challenge"),
            userName: options.user.name,
            displayName: options.user.displayName,
            userID: try Self.decodeBase64URL(options.user.id, fieldName: "user.id"),
            allowedCredentialIDs: [],
            excludedCredentialIDs: excludedCredentialIDs,
            userVerification: options.authenticatorSelection?.userVerification,
            attestation: options.attestation,
            exclusionHandling: .unsupportedByIOS16Minimum
        )
    }

    func makeAssertionRequest(
        options: PasskeyPublicKeyCredentialRequestOptions,
        allowedCredentialID: String? = nil
    ) throws -> PasskeyPlatformAuthorizationRequest {
        guard let relyingPartyID = nonEmpty(options.rpID) else {
            throw PasskeyPlatformAuthorizationError.invalidOptions("rpId")
        }

        let allowedCredentialIDs: [Data]
        if let allowedCredentialID {
            allowedCredentialIDs = [
                try Self.decodeBase64URL(allowedCredentialID, fieldName: "allowedCredentialID")
            ]
        } else {
            allowedCredentialIDs = try (options.allowCredentials ?? []).map {
                try Self.decodeBase64URL($0.id, fieldName: "allowCredentials.id")
            }
        }

        return PasskeyPlatformAuthorizationRequest(
            kind: .assertion,
            relyingPartyID: relyingPartyID,
            challenge: try Self.decodeBase64URL(options.challenge, fieldName: "challenge"),
            userName: nil,
            displayName: nil,
            userID: nil,
            allowedCredentialIDs: allowedCredentialIDs,
            excludedCredentialIDs: [],
            userVerification: options.userVerification,
            attestation: nil,
            exclusionHandling: .unsupportedByIOS16Minimum
        )
    }

    private func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult {
        guard activeAttempt == nil else {
            throw PasskeyPlatformAuthorizationError.authorizationAlreadyActive
        }

        guard presentationAnchorProvider() != nil else {
            throw PasskeyPlatformAuthorizationError.presentationAnchorUnavailable
        }

        let attempt = PasskeyPlatformAuthorizationAttempt(authorizationPerformer: authorizationPerformer)
        activeAttempt = attempt
        defer {
            if activeAttempt === attempt {
                activeAttempt = nil
            }
        }

        return try await withTaskCancellationHandler {
            try await attempt.perform(request)
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelActiveAuthorization()
            }
        }
    }

    private static func defaultPresentationAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    static func decodeBase64URL(_ value: String, fieldName: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingCount))

        guard let data = Data(base64Encoded: base64) else {
            throw PasskeyPlatformAuthorizationError.invalidOptions(fieldName)
        }
        return data
    }
}

@MainActor
private final class PasskeyPlatformAuthorizationAttempt {
    private let authorizationPerformer: any PasskeyPlatformAuthorizationRequestPerforming

    init(authorizationPerformer: any PasskeyPlatformAuthorizationRequestPerforming) {
        self.authorizationPerformer = authorizationPerformer
    }

    func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult {
        try await authorizationPerformer.perform(request)
    }

    func cancel() {
        authorizationPerformer.cancel()
    }
}

@MainActor
private final class ASPasskeyPlatformAuthorizationPerformer: NSObject, PasskeyPlatformAuthorizationRequestPerforming {
    private let presentationAnchorProvider: () -> ASPresentationAnchor?
    private var activeAttempt: ASAuthorizationControllerAttempt?

    init(presentationAnchorProvider: @escaping () -> ASPresentationAnchor?) {
        self.presentationAnchorProvider = presentationAnchorProvider
    }

    func perform(_ request: PasskeyPlatformAuthorizationRequest) async throws -> PasskeyPlatformCredentialResult {
        guard activeAttempt == nil else {
            throw PasskeyPlatformAuthorizationError.authorizationAlreadyActive
        }

        let authorizationRequest = try makeAuthorizationRequest(from: request)

        return try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [authorizationRequest])
            let attempt = ASAuthorizationControllerAttempt(
                controller: controller,
                expectedKind: request.kind,
                continuation: continuation
            )
            activeAttempt = attempt
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func cancel() {
        activeAttempt?.cancel()
        activeAttempt = nil
    }

    private func makeAuthorizationRequest(
        from request: PasskeyPlatformAuthorizationRequest
    ) throws -> ASAuthorizationRequest {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: request.relyingPartyID
        )

        switch request.kind {
        case .registration:
            guard let userName = request.userName,
                  let userID = request.userID
            else {
                throw PasskeyPlatformAuthorizationError.invalidOptions("user")
            }

            let authorizationRequest = provider.createCredentialRegistrationRequest(
                challenge: request.challenge,
                name: userName,
                userID: userID
            )
            authorizationRequest.displayName = request.displayName
            authorizationRequest.userVerificationPreference = userVerificationPreference(
                for: request.userVerification
            )
            authorizationRequest.attestationPreference = attestationPreference(for: request.attestation)
            return authorizationRequest
        case .assertion:
            let authorizationRequest = provider.createCredentialAssertionRequest(challenge: request.challenge)
            authorizationRequest.allowedCredentials = request.allowedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
            authorizationRequest.userVerificationPreference = userVerificationPreference(
                for: request.userVerification
            )
            return authorizationRequest
        }
    }

    private func userVerificationPreference(
        for value: String?
    ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch value {
        case "required":
            return .required
        case "discouraged":
            return .discouraged
        default:
            return .preferred
        }
    }

    private func attestationPreference(for value: String?) -> ASAuthorizationPublicKeyCredentialAttestationKind {
        switch value {
        case "direct":
            return .direct
        case "indirect":
            return .indirect
        case "enterprise":
            return .enterprise
        default:
            return .none
        }
    }
}

extension ASPasskeyPlatformAuthorizationPerformer: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let activeAttempt else {
            return
        }

        switch (activeAttempt.expectedKind, authorization.credential) {
        case (.registration, let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration):
            activeAttempt.resume(returning: .registration(PasskeyPlatformRegistrationCredential(
                credentialID: credential.credentialID,
                clientDataJSON: credential.rawClientDataJSON,
                attestationObject: credential.rawAttestationObject
            )))
        case (.assertion, let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion):
            activeAttempt.resume(returning: .assertion(PasskeyPlatformAssertionCredential(
                credentialID: credential.credentialID,
                clientDataJSON: credential.rawClientDataJSON,
                authenticatorData: credential.rawAuthenticatorData,
                signature: credential.signature,
                userID: credential.userID
            )))
        default:
            activeAttempt.resume(throwing: PasskeyPlatformAuthorizationError.invalidCredentialType)
        }

        self.activeAttempt = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let activeAttempt else {
            return
        }

        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            activeAttempt.resume(throwing: PasskeyPlatformAuthorizationError.canceled)
        } else {
            activeAttempt.resume(throwing: PasskeyPlatformAuthorizationError.authorizationFailed)
        }

        self.activeAttempt = nil
    }
}

extension ASPasskeyPlatformAuthorizationPerformer: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchorProvider() ?? ASPresentationAnchor()
    }
}

private final class ASAuthorizationControllerAttempt {
    let controller: ASAuthorizationController
    let expectedKind: PasskeyPlatformAuthorizationKind
    private var continuation: CheckedContinuation<PasskeyPlatformCredentialResult, Error>?

    init(
        controller: ASAuthorizationController,
        expectedKind: PasskeyPlatformAuthorizationKind,
        continuation: CheckedContinuation<PasskeyPlatformCredentialResult, Error>
    ) {
        self.controller = controller
        self.expectedKind = expectedKind
        self.continuation = continuation
    }

    deinit {
        resume(throwing: PasskeyPlatformAuthorizationError.canceled)
    }

    func cancel() {
        controller.cancel()
        resume(throwing: PasskeyPlatformAuthorizationError.canceled)
    }

    func resume(returning result: PasskeyPlatformCredentialResult) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

private extension PasskeyCredentialEnvelope {
    init(registrationCredential credential: PasskeyPlatformRegistrationCredential) {
        let credentialID = credential.credentialID.base64URLEncodedString()
        self.init(
            id: credentialID,
            rawID: credentialID,
            type: "public-key",
            response: .registration(PasskeyRegistrationCredentialResponse(
                clientDataJSON: credential.clientDataJSON.base64URLEncodedString(),
                attestationObject: credential.attestationObject?.base64URLEncodedString(),
                transports: nil
            ))
        )
    }

    init(assertionCredential credential: PasskeyPlatformAssertionCredential) {
        let credentialID = credential.credentialID.base64URLEncodedString()
        self.init(
            id: credentialID,
            rawID: credentialID,
            type: "public-key",
            response: .assertion(PasskeyAssertionCredentialResponse(
                clientDataJSON: credential.clientDataJSON.base64URLEncodedString(),
                authenticatorData: credential.authenticatorData.base64URLEncodedString(),
                signature: credential.signature.base64URLEncodedString(),
                userHandle: credential.userID.base64URLEncodedString()
            ))
        )
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
