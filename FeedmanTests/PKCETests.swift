import XCTest
@testable import Feedman

final class PKCETests: XCTestCase {
    func testGeneratedVerifierUsesDefaultMaximumLength() throws {
        let verifier = try PKCE.generateVerifier()

        XCTAssertEqual(verifier.count, PKCE.maximumVerifierLength)
    }

    func testGeneratedVerifierUsesAllowedCharactersOnly() throws {
        let verifier = try PKCE.generateVerifier()
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowedCharacters.contains($0) })
    }

    func testGeneratedVerifierCanUseMinimumLength() throws {
        let verifier = try PKCE.generateVerifier(length: PKCE.minimumVerifierLength)

        XCTAssertEqual(verifier.count, PKCE.minimumVerifierLength)
    }

    func testChallengeUsesRFC7636S256Example() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        let challenge = try PKCE.challenge(for: verifier)

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testChallengeDoesNotIncludeBase64PaddingOrStandardSeparators() throws {
        let verifier = try PKCE.generateVerifier(length: PKCE.minimumVerifierLength)

        let challenge = try PKCE.challenge(for: verifier)

        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testGenerationRejectsVerifierLengthBelowMinimum() {
        assertThrows(try PKCE.generateVerifier(length: PKCE.minimumVerifierLength - 1), PKCEError.invalidVerifierLength)
    }

    func testGenerationRejectsVerifierLengthAboveMaximum() {
        assertThrows(try PKCE.generateVerifier(length: PKCE.maximumVerifierLength + 1), PKCEError.invalidVerifierLength)
    }

    func testChallengeRejectsInvalidVerifierCharacter() {
        let verifier = String(repeating: "a", count: PKCE.minimumVerifierLength - 1) + "!"

        assertThrows(try PKCE.challenge(for: verifier), PKCEError.invalidVerifierCharacters)
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
