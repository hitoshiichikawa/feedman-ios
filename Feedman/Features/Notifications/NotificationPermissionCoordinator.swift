import Foundation
import UIKit
import UserNotifications

enum NotificationPermissionStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

extension NotificationPermissionStatus {
    var allowsRemoteRegistration: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        }
    }
}

protocol NotificationAuthorizationProviding {
    func currentStatus() async throws -> NotificationPermissionStatus
    func requestAuthorization() async throws -> NotificationPermissionStatus
}

protocol RemoteNotificationRegistering: AnyObject {
    @MainActor
    func registerForRemoteNotifications()
}

enum NotificationPermissionError: Error, Equatable {
    case requestFailed
}

final class UserNotificationCenterAuthorizationProvider: NotificationAuthorizationProviding {
    private let center: UNUserNotificationCenter
    private let options: UNAuthorizationOptions

    init(
        center: UNUserNotificationCenter = .current(),
        options: UNAuthorizationOptions = [.alert, .sound]
    ) {
        self.center = center
        self.options = options
    }

    func currentStatus() async throws -> NotificationPermissionStatus {
        let settings = await center.notificationSettings()
        return NotificationPermissionStatus(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> NotificationPermissionStatus {
        do {
            let granted = try await center.requestAuthorization(options: options)
            return granted ? .authorized : .denied
        } catch {
            throw NotificationPermissionError.requestFailed
        }
    }
}

@MainActor
final class UIApplicationRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

final class NotificationPermissionCoordinator {
    private let authorizationProvider: any NotificationAuthorizationProviding
    private let remoteNotificationRegistrar: any RemoteNotificationRegistering
    private let notificationFeatures: NotificationFeatureFlags

    init(
        authorizationProvider: any NotificationAuthorizationProviding,
        remoteNotificationRegistrar: any RemoteNotificationRegistering,
        notificationFeatures: NotificationFeatureFlags = .nextPhaseEnabled
    ) {
        self.authorizationProvider = authorizationProvider
        self.remoteNotificationRegistrar = remoteNotificationRegistrar
        self.notificationFeatures = notificationFeatures
    }

    @MainActor
    func requestPermissionAndRegisterIfAuthorized() async throws -> NotificationPermissionStatus {
        let currentStatus = try await authorizationProvider.currentStatus()
        let resolvedStatus: NotificationPermissionStatus

        if currentStatus == .notDetermined {
            resolvedStatus = try await authorizationProvider.requestAuthorization()
        } else {
            resolvedStatus = currentStatus
        }

        if notificationFeatures.keywordNotificationsEnabled, resolvedStatus.allowsRemoteRegistration {
            remoteNotificationRegistrar.registerForRemoteNotifications()
        }

        return resolvedStatus
    }
}

private extension NotificationPermissionStatus {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .denied
        }
    }
}
