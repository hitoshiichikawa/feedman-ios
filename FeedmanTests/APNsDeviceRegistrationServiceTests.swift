import XCTest
@testable import Feedman

final class APNsDeviceRegistrationServiceTests: XCTestCase {
    func testFormatterConvertsDeviceTokenToLowercaseHex() {
        let formatter = APNsDeviceTokenFormatter()
        let data = Data([0x00, 0x0F, 0x10, 0xAB, 0xFF])

        XCTAssertEqual(formatter.string(from: data), "000f10abff")
    }

    func testDeviceTokenWithoutAuthenticatedSessionDefersRegistration() async throws {
        let repository = RecordingDeviceRegistrationRepository()
        let store = InMemoryDeviceRegistrationStateStore()
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                throw AppEnvironmentError.missingAccessToken
            }
        )

        let result = try await service.registerDeviceToken(Data([0x00, 0xFF]))

        XCTAssertEqual(result, .deferredUntilAuthenticated)
        let requests = await repository.registerRequests
        XCTAssertEqual(requests, [])
        XCTAssertNil(store.load())
    }

    func testDeviceTokenRegistersWithHexTokenAndSavesDeviceID() async throws {
        let repository = RecordingDeviceRegistrationRepository(
            registerResults: [.success(DeviceRegistrationResponse(id: "device-1"))]
        )
        let store = InMemoryDeviceRegistrationStateStore()
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                "access-1"
            }
        )

        let result = try await service.registerDeviceToken(Data([0x00, 0xFF, 0x10]))

        XCTAssertEqual(result, .registered(deviceID: "device-1"))
        let requests = await repository.registerRequests
        XCTAssertEqual(
            requests,
            [DeviceRegisterRequest(pushToken: "00ff10", accessToken: "access-1")]
        )
        XCTAssertEqual(store.load(), DeviceRegistrationState(deviceID: "device-1"))
    }

    func testRepeatedSameTokenWhileInFlightAvoidsDuplicateRequest() async throws {
        let repository = BlockingDeviceRegistrationRepository()
        let store = InMemoryDeviceRegistrationStateStore()
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                "access-1"
            }
        )

        let firstTask = Task {
            try await service.registerDeviceToken(Data([0xAA]))
        }
        await waitForRegisterRequest(repository)

        let duplicateResult = try await service.registerDeviceToken(Data([0xAA]))
        XCTAssertEqual(duplicateResult, .alreadyInFlight)
        let requests = await repository.registerRequests
        XCTAssertEqual(requests.count, 1)

        await repository.succeed(with: DeviceRegistrationResponse(id: "device-1"))
        let firstResult = try await firstTask.value
        XCTAssertEqual(firstResult, .registered(deviceID: "device-1"))
    }

    func testRegistrationFailureKeepsTokenAvailableForRetry() async throws {
        let accessTokenBox = AccessTokenBox(result: .success("access-1"))
        let repository = RecordingDeviceRegistrationRepository(
            registerResults: [
                .failure(DeviceRegistrationTestError.rejected),
                .success(DeviceRegistrationResponse(id: "device-1"))
            ]
        )
        let store = InMemoryDeviceRegistrationStateStore()
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                try await accessTokenBox.currentAccessToken()
            }
        )

        do {
            _ = try await service.registerDeviceToken(Data([0xAB]))
            XCTFail("Expected registration failure")
        } catch DeviceRegistrationTestError.rejected {
            XCTAssertNil(store.load())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let retryResult = try await service.retryPendingRegistrationIfPossible()

        XCTAssertEqual(retryResult, .registered(deviceID: "device-1"))
        let requests = await repository.registerRequests
        XCTAssertEqual(
            requests,
            [
                DeviceRegisterRequest(pushToken: "ab", accessToken: "access-1"),
                DeviceRegisterRequest(pushToken: "ab", accessToken: "access-1")
            ]
        )
    }

    func testLogoutUnregisterDeletesKnownDeviceAndClearsState() async {
        let repository = RecordingDeviceRegistrationRepository()
        let store = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                "access-1"
            }
        )

        let result = await service.unregisterKnownDeviceForLogout(accessToken: "access-1")

        XCTAssertEqual(try? result.get(), .unregistered(deviceID: "device-1"))
        let unregisterRequests = await repository.unregisterRequests
        XCTAssertEqual(
            unregisterRequests,
            [DeviceUnregisterRequest(deviceID: "device-1", accessToken: "access-1")]
        )
        XCTAssertNil(store.load())
    }

    func testLogoutUnregisterFailureReturnsFailureAndStillClearsState() async {
        let repository = RecordingDeviceRegistrationRepository(
            unregisterResults: [.failure(DeviceRegistrationTestError.rejected)]
        )
        let store = InMemoryDeviceRegistrationStateStore(
            state: DeviceRegistrationState(deviceID: "device-1")
        )
        let service = APNsDeviceRegistrationService(
            repository: repository,
            stateStore: store,
            accessTokenProvider: {
                "access-1"
            }
        )

        let result = await service.unregisterKnownDeviceForLogout(accessToken: "access-1")

        switch result {
        case .success:
            XCTFail("Expected unregister failure")
        case .failure(let error):
            XCTAssertTrue(error is DeviceRegistrationTestError)
        }
        XCTAssertNil(store.load())
        let unregisterRequests = await repository.unregisterRequests
        XCTAssertEqual(unregisterRequests.count, 1)
    }

    private func waitForRegisterRequest(
        _ repository: BlockingDeviceRegistrationRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            if await repository.registerRequests.count == 1 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for registration request", file: file, line: line)
    }
}

private struct DeviceRegisterRequest: Equatable {
    let pushToken: String
    let accessToken: String
}

private struct DeviceUnregisterRequest: Equatable {
    let deviceID: String
    let accessToken: String
}

private actor RecordingDeviceRegistrationRepository: DeviceRegistrationRepository {
    private(set) var registerRequests: [DeviceRegisterRequest] = []
    private(set) var unregisterRequests: [DeviceUnregisterRequest] = []
    private var registerResults: [Result<DeviceRegistrationResponse, Error>]
    private var unregisterResults: [Result<Void, Error>]

    init(
        registerResults: [Result<DeviceRegistrationResponse, Error>] = [],
        unregisterResults: [Result<Void, Error>] = []
    ) {
        self.registerResults = registerResults
        self.unregisterResults = unregisterResults
    }

    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        registerRequests.append(DeviceRegisterRequest(pushToken: pushToken, accessToken: accessToken))
        if registerResults.isEmpty {
            return DeviceRegistrationResponse(id: "device-1")
        }
        return try registerResults.removeFirst().get()
    }

    func unregisterDevice(id: String, accessToken: String) async throws {
        unregisterRequests.append(DeviceUnregisterRequest(deviceID: id, accessToken: accessToken))
        if unregisterResults.isEmpty {
            return
        }
        try unregisterResults.removeFirst().get()
    }
}

private actor BlockingDeviceRegistrationRepository: DeviceRegistrationRepository {
    private(set) var registerRequests: [DeviceRegisterRequest] = []
    private var continuation: CheckedContinuation<DeviceRegistrationResponse, Error>?

    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        registerRequests.append(DeviceRegisterRequest(pushToken: pushToken, accessToken: accessToken))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func unregisterDevice(id: String, accessToken: String) async throws {}

    func succeed(with response: DeviceRegistrationResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private actor AccessTokenBox {
    private let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func currentAccessToken() throws -> String {
        try result.get()
    }
}

private enum DeviceRegistrationTestError: Error {
    case rejected
}
