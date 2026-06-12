import AuthenticationServices
import Foundation
import UIKit

enum FeedmanWebAuthenticationError: Error, Equatable {
    case canceled
    case sessionAlreadyActive
    case presentationAnchorUnavailable
    case unableToStart
}

@MainActor
protocol WebAuthenticationSessionStarting {
    func start(url: URL, callbackURLScheme: String) async throws -> URL
}

@MainActor
final class ASWebAuthenticationSessionCoordinator: NSObject, WebAuthenticationSessionStarting {
    private var activeSession: ASWebAuthenticationSession?

    func start(url: URL, callbackURLScheme: String) async throws -> URL {
        guard activeSession == nil else {
            throw FeedmanWebAuthenticationError.sessionAlreadyActive
        }

        guard presentationAnchor() != nil else {
            throw FeedmanWebAuthenticationError.presentationAnchorUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.activeSession = nil

                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                        return
                    }

                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin {
                        continuation.resume(throwing: FeedmanWebAuthenticationError.canceled)
                        return
                    }

                    continuation.resume(throwing: error ?? FeedmanWebAuthenticationError.unableToStart)
                }
            }

            session.presentationContextProvider = self
            activeSession = session

            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: FeedmanWebAuthenticationError.unableToStart)
            }
        }
    }
}

extension ASWebAuthenticationSessionCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor() ?? ASPresentationAnchor()
    }

    private func presentationAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
