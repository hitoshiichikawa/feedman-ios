import XCTest
@testable import Feedman

final class AuthCallbackParserTests: XCTestCase {
    func testParserExtractsAuthCodeFromCallbackURL() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/callback?auth_code=one-time-code"))

        let authCode = try AuthCallbackParser.authCode(from: url)

        XCTAssertEqual(authCode, "one-time-code")
    }

    func testParserDecodesPercentEncodedAuthCode() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/callback?auth_code=one%20time%2Fcode"))

        let authCode = try AuthCallbackParser.authCode(from: url)

        XCTAssertEqual(authCode, "one time/code")
    }

    func testParserIgnoresUnrelatedQueryParameters() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/callback?state=unused&auth_code=abc123"))

        let authCode = try AuthCallbackParser.authCode(from: url)

        XCTAssertEqual(authCode, "abc123")
    }

    func testParserRejectsWrongScheme() throws {
        let url = try XCTUnwrap(URL(string: "https://auth/callback?auth_code=abc123"))

        assertThrows(try AuthCallbackParser.authCode(from: url), AuthCallbackParserError.invalidScheme)
    }

    func testParserRejectsWrongHost() throws {
        let url = try XCTUnwrap(URL(string: "feedman://oauth/callback?auth_code=abc123"))

        assertThrows(try AuthCallbackParser.authCode(from: url), AuthCallbackParserError.invalidPath)
    }

    func testParserRejectsWrongPath() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/complete?auth_code=abc123"))

        assertThrows(try AuthCallbackParser.authCode(from: url), AuthCallbackParserError.invalidPath)
    }

    func testParserRejectsMissingAuthCode() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/callback?state=unused"))

        assertThrows(try AuthCallbackParser.authCode(from: url), AuthCallbackParserError.missingAuthCode)
    }

    func testParserRejectsEmptyAuthCode() throws {
        let url = try XCTUnwrap(URL(string: "feedman://auth/callback?auth_code="))

        assertThrows(try AuthCallbackParser.authCode(from: url), AuthCallbackParserError.missingAuthCode)
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
