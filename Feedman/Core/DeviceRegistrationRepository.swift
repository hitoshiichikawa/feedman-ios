import Foundation

protocol DeviceRegistrationRepository {
    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse
    func unregisterDevice(id: String, accessToken: String) async throws
}

struct APIClientDeviceRegistrationRepository: DeviceRegistrationRepository {
    let apiClient: APIClient

    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        try await apiClient.send(
            DeviceRegistrationResponse.self,
            method: .post,
            path: "/api/devices",
            body: DeviceRegistrationRequest(platform: "ios", pushToken: pushToken),
            accessToken: accessToken
        )
    }

    func unregisterDevice(id: String, accessToken: String) async throws {
        try await apiClient.sendNoContent(
            method: .delete,
            path: "/api/devices/\(id)",
            accessToken: accessToken
        )
    }
}

struct UnavailableDeviceRegistrationRepository: DeviceRegistrationRepository {
    func registerDevice(pushToken: String, accessToken: String) async throws -> DeviceRegistrationResponse {
        throw DeviceRegistrationRepositoryError.authenticatedSessionUnavailable
    }

    func unregisterDevice(id: String, accessToken: String) async throws {
        throw DeviceRegistrationRepositoryError.authenticatedSessionUnavailable
    }
}

enum DeviceRegistrationRepositoryError: Error, Equatable {
    case authenticatedSessionUnavailable
}

struct DeviceRegistrationState: Codable, Equatable {
    let deviceID: String
}

protocol DeviceRegistrationStateStore {
    func load() -> DeviceRegistrationState?
    func save(_ state: DeviceRegistrationState)
    func clear()
}

final class UserDefaultsDeviceRegistrationStateStore: DeviceRegistrationStateStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "feedman.device-registration-state"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> DeviceRegistrationState? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(DeviceRegistrationState.self, from: data)
    }

    func save(_ state: DeviceRegistrationState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
