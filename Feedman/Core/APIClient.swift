import Foundation

protocol APITransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: APITransport {}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

struct APIClient {
    typealias AccessTokenRefreshHook = @Sendable () async throws -> String

    let baseURL: URL

    private let transport: APITransport
    private let encoder: JSONEncoder
    private let responseDecoder: APIResponseDecoder
    private let accessTokenRefreshHook: AccessTokenRefreshHook?
    private let refreshCoordinator: AccessTokenRefreshCoordinator

    init(
        baseURL: URL,
        transport: APITransport = URLSession.shared,
        encoder: JSONEncoder = JSONEncoder(),
        responseDecoder: APIResponseDecoder = APIResponseDecoder(),
        accessTokenRefreshHook: AccessTokenRefreshHook? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.encoder = encoder
        self.responseDecoder = responseDecoder
        self.accessTokenRefreshHook = accessTokenRefreshHook
        self.refreshCoordinator = AccessTokenRefreshCoordinator()
    }

    func send<Response: Decodable>(
        _ responseType: Response.Type,
        method: HTTPMethod = .get,
        path: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> Response {
        let request = try makeRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: Optional<Data>.none,
            accessToken: accessToken
        )
        return try await send(responseType, request: request)
    }

    func send<Response: Decodable, Body: Encodable>(
        _ responseType: Response.Type,
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil
    ) async throws -> Response {
        let request = try makeRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            accessToken: accessToken
        )
        return try await send(responseType, request: request)
    }

    /// 204 No Content のような body を持たない成功応答を期待する request を送信する。
    func sendNoContent<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil
    ) async throws {
        let request = try makeRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            accessToken: accessToken
        )
        let (data, httpResponse) = try await performWithRefreshRetry(request)
        try responseDecoder.validateNoContent(from: data, response: httpResponse)
    }

    func makeRequest<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body?,
        accessToken: String? = nil
    ) throws -> URLRequest {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func send<Response: Decodable>(
        _ responseType: Response.Type,
        request: URLRequest
    ) async throws -> Response {
        let (data, httpResponse) = try await performWithRefreshRetry(request)
        return try responseDecoder.decode(responseType, from: data, response: httpResponse)
    }

    private func performWithRefreshRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, httpResponse) = try await perform(request)
        guard shouldRefresh(for: request, response: httpResponse) else {
            return (data, httpResponse)
        }

        let refreshedAccessToken = try await refreshAccessToken(
            after: data,
            response: httpResponse
        )

        var retryRequest = request
        retryRequest.setValue("Bearer \(refreshedAccessToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await perform(retryRequest)
        if retryResponse.statusCode == 401 {
            throw FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .retryUnauthorized,
                    statusCode: retryResponse.statusCode,
                    underlyingError: responseDecoder.error(from: retryData, response: retryResponse)
                )
            )
        }

        return (retryData, retryResponse)
    }

    private func shouldRefresh(for request: URLRequest, response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 401 else {
            return false
        }

        return request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
    }

    private func refreshAccessToken(
        after data: Data,
        response: HTTPURLResponse
    ) async throws -> String {
        guard let accessTokenRefreshHook else {
            throw FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .missingRefreshHook,
                    statusCode: response.statusCode,
                    underlyingError: responseDecoder.error(from: data, response: response)
                )
            )
        }

        do {
            return try await refreshCoordinator.refresh(using: accessTokenRefreshHook)
        } catch {
            throw FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .refreshFailed,
                    statusCode: response.statusCode,
                    underlyingError: error
                )
            )
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw FeedmanAPIError.transportFailed(underlyingError: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedmanAPIError.nonHTTPResponse(response)
        }

        return (data, httpResponse)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw FeedmanAPIError.invalidRequestURL(path: path)
        }

        let endpoint = endpointComponents(from: path)
        let joinedPath = joinPaths(baseComponents.percentEncodedPath, endpoint.percentEncodedPath)
        baseComponents.percentEncodedPath = joinedPath.isEmpty ? "/" : joinedPath

        let mergedQueryItems = (baseComponents.queryItems ?? [])
            + (endpoint.queryItems ?? [])
            + queryItems
        baseComponents.queryItems = mergedQueryItems.isEmpty ? nil : mergedQueryItems

        guard let url = baseComponents.url else {
            throw FeedmanAPIError.invalidRequestURL(path: path)
        }
        return url
    }

    private func endpointComponents(from path: String) -> URLComponents {
        var components = URLComponents()

        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = String(parts.first ?? "")
        if parts.count == 2 {
            components.query = String(parts[1])
        }

        return components
    }

    private func joinPaths(_ basePath: String, _ endpointPath: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedEndpoint = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch (trimmedBase.isEmpty, trimmedEndpoint.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return "/" + trimmedEndpoint
        case (false, true):
            return "/" + trimmedBase
        case (false, false):
            return "/" + trimmedBase + "/" + trimmedEndpoint
        }
    }
}

private actor AccessTokenRefreshCoordinator {
    private var inFlightTask: Task<String, Error>?

    func refresh(using hook: @escaping APIClient.AccessTokenRefreshHook) async throws -> String {
        if let inFlightTask {
            return try await inFlightTask.value
        }

        let task = Task {
            try await hook()
        }
        inFlightTask = task
        defer {
            inFlightTask = nil
        }

        return try await task.value
    }
}
