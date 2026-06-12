import Foundation

struct APIResponseDecoder {
    let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        response: HTTPURLResponse
    ) throws -> T {
        if Self.successStatusCodes.contains(response.statusCode) {
            do {
                return try decoder.decode(type, from: data)
            } catch {
                throw FeedmanAPIError.successDecodingFailed(underlyingError: error)
            }
        }

        throw failureError(from: data, response: response)
    }

    /// 204 No Content のような body を持たない成功応答の検証。
    /// 2xx は body を decode せず成功とし、非 2xx は `decode` と同一の error 変換を適用する。
    func validateNoContent(from data: Data, response: HTTPURLResponse) throws {
        guard Self.successStatusCodes.contains(response.statusCode) else {
            throw failureError(from: data, response: response)
        }
    }

    private func failureError(from data: Data, response: HTTPURLResponse) -> FeedmanAPIError {
        do {
            let errorResponse = try decoder.decode(FeedmanErrorResponse.self, from: data)
            return FeedmanAPIError.feedmanError(
                FeedmanErrorContext(
                    statusCode: response.statusCode,
                    body: errorResponse.error,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                )
            )
        } catch {
            return FeedmanAPIError.malformedErrorResponse(
                MalformedFeedmanErrorContext(
                    statusCode: response.statusCode,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                    body: data,
                    underlyingError: error
                )
            )
        }
    }

    private static let successStatusCodes = 200..<300
}

enum FeedmanAPIError: Error {
    case feedmanError(FeedmanErrorContext)
    case malformedErrorResponse(MalformedFeedmanErrorContext)
    case successDecodingFailed(underlyingError: Error)
    case invalidRequestURL(path: String)
    case nonHTTPResponse(URLResponse)
    case transportFailed(underlyingError: Error)
}

struct FeedmanErrorContext: Equatable {
    let statusCode: Int
    let body: FeedmanErrorBody
    let retryAfter: String?

    var code: String {
        body.code
    }

    var message: String {
        body.message
    }

    var category: String {
        body.category
    }

    var action: String {
        body.action
    }

    var retryAfterSeconds: Int? {
        body.details?["retry_after_seconds"]?.intValue
    }
}

struct MalformedFeedmanErrorContext {
    let statusCode: Int
    let retryAfter: String?
    let body: Data
    let underlyingError: Error
}
