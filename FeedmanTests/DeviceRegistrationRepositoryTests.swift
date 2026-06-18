import XCTest
@testable import Feedman

final class DeviceRegistrationRepositoryTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testRegisterDevicePostsIOSPlatformAndPushTokenWithBearer() async throws {
        let transport = DeviceRegistrationRecordingTransport()
        transport.enqueue(data: Data(#"{"id":"device-1"}"#.utf8), statusCode: 200)
        let repository = APIClientDeviceRegistrationRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        let response = try await repository.registerDevice(
            pushToken: "00ff10",
            accessToken: "access-1"
        )

        XCTAssertEqual(response.id, "device-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/devices")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["platform"], "ios")
        XCTAssertEqual(json["push_token"], "00ff10")
    }

    func testUnregisterDeviceDeletesDeviceWithBearer() async throws {
        let transport = DeviceRegistrationRecordingTransport()
        transport.enqueue(data: Data(), statusCode: 204)
        let repository = APIClientDeviceRegistrationRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        try await repository.unregisterDevice(id: "device-1", accessToken: "access-1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/devices/device-1")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertNil(request.httpBody)
    }

    func testRegisterDeviceDelegatesExpiredTokenRefreshToAPIClient() async throws {
        let transport = DeviceRegistrationRecordingTransport()
        transport.enqueue(data: feedmanErrorData(code: "ACCESS_TOKEN_EXPIRED"), statusCode: 401)
        transport.enqueue(data: Data(#"{"id":"device-1"}"#.utf8), statusCode: 200)
        let refreshHook = DeviceRegistrationRefreshHook(accessToken: "access-2")
        let repository = APIClientDeviceRegistrationRepository(
            apiClient: APIClient(
                baseURL: baseURL,
                transport: transport,
                accessTokenRefreshHook: {
                    await refreshHook.refresh()
                }
            )
        )

        let response = try await repository.registerDevice(pushToken: "00ff10", accessToken: "access-1")

        XCTAssertEqual(response.id, "device-1")
        let refreshCallCount = await refreshHook.callCount
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(
            transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer access-1", "Bearer access-2"]
        )
    }

    func testDeviceRegistrationResponseDecodesID() throws {
        let response = try JSONDecoder().decode(
            DeviceRegistrationResponse.self,
            from: Data(#"{"id":"device-1"}"#.utf8)
        )

        XCTAssertEqual(response.id, "device-1")
    }

    private func feedmanErrorData(code: String) -> Data {
        Data(
            """
            {
              "error": {
                "code": "\(code)",
                "message": "Authentication is required.",
                "category": "auth",
                "action": "login"
              }
            }
            """.utf8
        )
    }
}

private final class DeviceRegistrationRecordingTransport: APITransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var queuedResults: [(Data, Int)] = []

    func enqueue(data: Data, statusCode: Int) {
        queuedResults.append((data, statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queuedResults.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let (data, statusCode) = queuedResults.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor DeviceRegistrationRefreshHook {
    private let accessToken: String
    private(set) var callCount = 0

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func refresh() -> String {
        callCount += 1
        return accessToken
    }
}
