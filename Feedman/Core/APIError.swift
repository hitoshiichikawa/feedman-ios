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

        do {
            let errorResponse = try decoder.decode(FeedmanErrorResponse.self, from: data)
            throw FeedmanAPIError.feedmanError(
                FeedmanErrorContext(
                    statusCode: response.statusCode,
                    body: errorResponse.error,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                )
            )
        } catch let error as FeedmanAPIError {
            throw error
        } catch {
            throw FeedmanAPIError.malformedErrorResponse(
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
