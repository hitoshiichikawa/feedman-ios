import CryptoKit
import Foundation
import Security

enum PKCEError: Error, Equatable {
    case invalidVerifierLength
    case invalidVerifierCharacters
    case randomGenerationFailed
}

enum PKCE {
    static let minimumVerifierLength = 43
    static let maximumVerifierLength = 128

    private static let verifierAlphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
    private static let allowedVerifierScalars = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".unicodeScalars
    )

    static func generateVerifier(length: Int = maximumVerifierLength) throws -> String {
        guard minimumVerifierLength...maximumVerifierLength ~= length else {
            throw PKCEError.invalidVerifierLength
        }

        var characters: [Character] = []
        characters.reserveCapacity(length)

        let alphabetCount = verifierAlphabet.count
        let maximumUnbiasedByte = Int(UInt8.max) - (Int(UInt8.max) % alphabetCount)

        while characters.count < length {
            let remainingCount = length - characters.count
            let byteCount = max(remainingCount * 2, 32)
            var bytes = [UInt8](repeating: 0, count: byteCount)

            let status = bytes.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }

            guard status == errSecSuccess else {
                throw PKCEError.randomGenerationFailed
            }

            for byte in bytes where Int(byte) < maximumUnbiasedByte {
                characters.append(verifierAlphabet[Int(byte) % alphabetCount])

                if characters.count == length {
                    break
                }
            }
        }

        return String(characters)
    }

    static func challenge(for verifier: String) throws -> String {
        try validateVerifier(verifier)

        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func validateVerifier(_ verifier: String) throws {
        guard minimumVerifierLength...maximumVerifierLength ~= verifier.count else {
            throw PKCEError.invalidVerifierLength
        }

        guard verifier.unicodeScalars.allSatisfy(allowedVerifierScalars.contains) else {
            throw PKCEError.invalidVerifierCharacters
        }
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
