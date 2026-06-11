import XCTest
@testable import Feedman

final class APIResponseDecoderTests: XCTestCase {
    private let decoder = APIResponseDecoder()

    func testNonSuccessResponseWithFeedmanErrorSurfacesTypedAppError() throws {
        let response = try httpResponse(statusCode: 429, headers: ["Retry-After": "120"])
        let data = try fixtureData(named: "feedman_error_cooldown")

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 429)
            XCTAssertEqual(context.retryAfter, "120")
            XCTAssertEqual(context.code, "FEED_COOLDOWN")
            XCTAssertEqual(context.message, "Feed fetch is cooling down.")
            XCTAssertEqual(context.category, "rate_limit")
            XCTAssertEqual(context.action, "retry_later")
            XCTAssertEqual(context.body.details?["feed_id"]?.stringValue, "feed-publickey")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFeedCooldownRetrySecondsAreInspectableFromTypedAppError() throws {
        let response = try httpResponse(statusCode: 429, headers: ["Retry-After": "120"])
        let data = try fixtureData(named: "feedman_error_cooldown")

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.retryAfterSeconds, 120)
            XCTAssertEqual(context.retryAfter, "120")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFeedmanErrorWithoutDetailsDecodesAsNilDetails() throws {
        let response = try httpResponse(statusCode: 400)
        let data = Data(
            """
            {
              "error": {
                "code": "INVALID_GRANT",
                "message": "Authorization grant is invalid.",
                "category": "auth",
                "action": "login_again"
              }
            }
            """.utf8
        )

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            XCTAssertEqual(context.statusCode, 400)
            XCTAssertEqual(context.code, "INVALID_GRANT")
            XCTAssertNil(context.body.details)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFeedmanErrorDetailsPreserveJSONValues() throws {
        let response = try httpResponse(statusCode: 400)
        let data = Data(
            """
            {
              "error": {
                "code": "VALIDATION_FAILED",
                "message": "Request is invalid.",
                "category": "validation",
                "action": "fix_request",
                "details": {
                  "field": "url",
                  "attempts": 2,
                  "temporary": false,
                  "nested": { "reason": "unsupported_scheme" },
                  "allowed": ["https", "http"],
                  "missing": null
                }
              }
            }
            """.utf8
        )

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.feedmanError")
        } catch FeedmanAPIError.feedmanError(let context) {
            let details = try XCTUnwrap(context.body.details)
            XCTAssertEqual(details["field"], .string("url"))
            XCTAssertEqual(details["attempts"], .int(2))
            XCTAssertEqual(details["temporary"], .bool(false))
            XCTAssertEqual(details["nested"], .object(["reason": .string("unsupported_scheme")]))
            XCTAssertEqual(details["allowed"], .array([.string("https"), .string("http")]))
            XCTAssertEqual(details["missing"], .null)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidJSONNonSuccessErrorBodySurfacesDecodeFailure() throws {
        let response = try httpResponse(statusCode: 502)
        let data = Data("not-json".utf8)

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.malformedErrorResponse")
        } catch FeedmanAPIError.malformedErrorResponse(let context) {
            XCTAssertEqual(context.statusCode, 502)
            XCTAssertEqual(context.body, data)
            XCTAssertTrue(context.underlyingError is DecodingError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedNonSuccessErrorBodySurfacesDecodeFailure() throws {
        let response = try httpResponse(statusCode: 500, headers: ["Retry-After": "30"])
        let data = Data(#"{"error":{"code":"SERVER_ERROR"}}"#.utf8)

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.malformedErrorResponse")
        } catch FeedmanAPIError.malformedErrorResponse(let context) {
            XCTAssertEqual(context.statusCode, 500)
            XCTAssertEqual(context.retryAfter, "30")
            XCTAssertEqual(context.body, data)
            XCTAssertTrue(context.underlyingError is DecodingError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessBodyDecodeFailureIsNotFeedmanErrorDecodeFailure() throws {
        let response = try httpResponse(statusCode: 200)
        let data = Data(#"{"error":{"code":"FEED_COOLDOWN"}}"#.utf8)

        do {
            let _: EmptySuccessResponse = try decoder.decode(EmptySuccessResponse.self, from: data, response: response)
            XCTFail("Expected FeedmanAPIError.successDecodingFailed")
        } catch FeedmanAPIError.successDecodingFailed(let underlyingError) {
            XCTAssertTrue(underlyingError is DecodingError)
        } catch FeedmanAPIError.malformedErrorResponse {
            XCTFail("Success decode failure must not be surfaced as malformed Feedman error body")
        } catch FeedmanAPIError.feedmanError {
            XCTFail("Success decode failure must not be surfaced as Feedman error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func httpResponse(
        statusCode: Int,
        headers: [String: String]? = nil
    ) throws -> HTTPURLResponse {
        try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://api.example.com/test")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private struct EmptySuccessResponse: Decodable {
    let ok: Bool
}
