## Implementation Notes

### Task 1

- 採用方針: `AppEnvironment.production()` に `NotificationFeatureFlags` を注入可能にし、default は `.v1Default` として keyword / device の next phase API dependency を active graph から外した。
- 重要な判断: enabled path は `.nextPhaseEnabled` を明示した場合だけ `APIClientKeywordRepository` / `APIClientDeviceRegistrationRepository` を使う構成にした。disabled keyword path は `APIClient` を保持しない `DisabledKeywordRepository` とし、誤到達しても network transport に依存しない。
- 残存課題: APNs service の runtime short-circuit、permission coordinator、AppShell drawer gating、README smoke checklist は後続 task の scope。

#### Task 1 AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 1.1 | `AppEnvironment.production(notificationFeatures:)`, `NotificationFeatureFlags.v1Default` | `FeedmanApp` の `AppEnvironment.production()` default | `testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` が `.v1Default` と `keywordNotificationsEnabled == false` を検証 | `xcodebuild ... -only-testing:... test` 成功 | Remote config / server dependency なし |
| 1.2 | `AppEnvironment.production(notificationFeatures:)` の device repository 分岐 | Production dependency graph | `testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` が default で `APIClientDeviceRegistrationRepository` ではないことを検証 | `xcodebuild ... -only-testing:... test` 成功 | runtime retry short-circuit は task 2 scope |
| 1.3 | `DisabledKeywordRepository`, production keyword repository 分岐 | Production dependency graph / keyword repository boundary | `testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies`, `testDisabledKeywordRepositoryFailsWithoutNetworkDependency` | `xcodebuild ... -only-testing:... test` 成功 | UI route gating は task 4 scope |
| 1.4 | `.nextPhaseEnabled` explicit configuration | Explicit enabled production configuration | `testProductionEnvironmentCanEnableNotificationDependenciesExplicitly` が既存 API repositories を検証 | `xcodebuild ... -only-testing:... test` 成功 | 既存 request contract tests は削除なし |
| 1.5 | `NotificationFeatureFlags` value injection | `AppEnvironment.production(notificationFeatures:)` | `testProductionEnvironmentCanEnableNotificationDependenciesExplicitly` が explicit injection を検証 | `xcodebuild ... -only-testing:... test` 成功 | Remote config / server dependency なし |
| 5.2 | `AppEnvironment.production()` default dependency graph, `DisabledKeywordRepository` | Production default / repository boundary | `testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies`, `testDisabledKeywordRepositoryFailsWithoutNetworkDependency` | `xcodebuild ... -only-testing:... test` 成功 | login / restore / logout の device runtime regression は task 2 scope |

#### Verification

- `git diff --check`: 成功
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/AppEnvironmentSessionRestoreTests/testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies -only-testing:FeedmanTests/AppEnvironmentSessionRestoreTests/testProductionEnvironmentCanEnableNotificationDependenciesExplicitly -only-testing:FeedmanTests/KeywordRepositoryTests/testDisabledKeywordRepositoryFailsWithoutNetworkDependency test`: 成功

STATUS: complete

### Task 2

- 採用方針: `APNsDeviceRegistrationService` 自体に `NotificationFeatureFlags` を注入し、disabled 時は token registration / retry / logout unregister を repository と access token provider の手前で short-circuit する。
- 重要な判断: disabled path は stale `DeviceRegistrationState` を `clearLocalState()` で best-effort cleanup し、logout は `.skippedFeatureDisabled` の success outcome として auth state transition を継続させる。enabled path の既存 initializer default は `.nextPhaseEnabled` に保ち、既存テストと next phase behavior を維持した。
- 残存課題: permission coordinator の remote notification registration 抑止は task 3、AppShell drawer / keyword sheet gating は task 4、README smoke checklist は task 6 の scope。

#### Task 2 AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 3.1 | `APNsDeviceRegistrationService.registerPushToken(_:)` disabled guard | `APNsDeviceRegistrationBridge.handleDeviceToken(_:)` APNs callback | `testDisabledAPNsDeviceTokenCallbackDoesNotPostDeviceRegistration`, `testDisabledDeviceTokenRegistrationSkipsRepositoryAndClearsState` が repository call count 0 と access token provider call count 0 を検証 | `xcodebuild ... -only-testing:FeedmanTests/APNsDeviceRegistrationServiceTests -only-testing:FeedmanTests/AppEnvironmentSessionRestoreTests -only-testing:FeedmanTests/AppEnvironmentLogoutTests test` 成功 | 実 APNs / 実 network 不使用 |
| 3.3 | `AppEnvironment.completeLogin(with:)` -> `retryPendingDeviceRegistrationIfPossible()` -> service disabled guard | Login completion flow | `testDisabledCompleteLoginRetryDoesNotPostDeviceRegistration` が login 後も `/api/devices` 相当 repository call 0 と retry error nil を検証 | 同上 成功 | disabled token callback は pending token を保持しない |
| 3.4 | `AppEnvironment.restoreSessionAtLaunch()` -> `retryPendingDeviceRegistrationIfPossible()` -> service disabled guard | Session restore flow | `testDisabledRestoreRetryDoesNotPostDeviceRegistration` が restore success 後も repository call 0 と retry error nil を検証 | 同上 成功 | refresh token restore 自体は既存 flow を維持 |
| 3.5 | `APNsDeviceRegistrationService.unregisterKnownDeviceForLogout(accessToken:)` disabled guard | `AppEnvironment.logout()` | `testDisabledLogoutSkipsDeviceUnregisterClearsStateAndShowsLogin`, `testDisabledLogoutUnregisterSkipsRepositoryAndClearsKnownDevice` が DELETE 相当 repository call 0 を検証 | 同上 成功 | auth revoke / unauthenticated transition は継続 |
| 3.6 | `APNsDeviceRegistrationService.clearLocalState()` reused by disabled register / retry / logout | Disabled APNs callback and logout cleanup | `testDisabledDeviceTokenRegistrationSkipsRepositoryAndClearsState`, `testDisabledAPNsDeviceTokenCallbackDoesNotPostDeviceRegistration`, `testDisabledLogoutSkipsDeviceUnregisterClearsStateAndShowsLogin` が stale state clear を検証 | 同上 成功 | network 成功に依存しない cleanup |
| 3.7 | service initializer default `.nextPhaseEnabled`; existing enabled repository path unchanged | Enabled APNs registration / retry / unregister flows | `testDeviceTokenRegistersWithHexTokenAndSavesDeviceID`, `testRegistrationFailureKeepsTokenAvailableForRetry`, `testLogoutUnregisterDeletesKnownDeviceAndClearsState`, existing AppEnvironment enabled retry tests | 同上 成功 | request contract tests は削除なし |
| 5.2 | `AppEnvironment.production(notificationFeatures:)` passes flags to APNs service; service disabled guard | Production default runtime dependency / APNs service boundary | `testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` と task 2 disabled runtime tests が no-network path を検証 | 同上 成功 / `git diff --check` 成功 | keyword repository no-network は task 1 で検証済み |
| 5.3 | `.nextPhaseEnabled` and default service init preserve existing enabled behavior | Enabled configuration unit coverage | `testProductionEnvironmentCanEnableNotificationDependenciesExplicitly` と APNs enabled-path tests が既存 flow を検証 | 同上 成功 | task 5 で next phase repository / ViewModel coverage を最終確認予定 |

#### Verification

- Red 確認: 新規 disabled-path tests 追加直後の targeted `xcodebuild ... test` は `featureFlags` initializer / `.skippedFeatureDisabled` 未実装により compile failure（期待どおり）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/APNsDeviceRegistrationServiceTests -only-testing:FeedmanTests/AppEnvironmentSessionRestoreTests -only-testing:FeedmanTests/AppEnvironmentLogoutTests test`: 成功
- `git diff --check`: 成功
- Reviewer Findings: round 1 は task 1 approve / Findings なしのため closure 対応なし。

STATUS: complete

### Task 3

- 採用方針: `NotificationPermissionCoordinator` に `NotificationFeatureFlags` を注入し、disabled 時は authorization status が remote registration 可能でも registrar 呼び出しを短絡する。
- 重要な判断: coordinator initializer の default は `.nextPhaseEnabled` に保ち、既存の enabled-path permission tests を変更せず維持した。`AppEnvironment.production(notificationFeatures:)` から同じ flag を coordinator に渡し、production default の source of truth を task 1/2 と揃えた。
- 残存課題: AppShell drawer / keyword settings sheet gating は task 4、README smoke checklist は task 6 の scope。

#### Task 3 AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 3.2 | `NotificationPermissionCoordinator.requestPermissionAndRegisterIfAuthorized()` の `notificationFeatures.keywordNotificationsEnabled` guard / `AppEnvironment.production(notificationFeatures:)` coordinator wiring | Permission request flow -> `RemoteNotificationRegistering.registerForRemoteNotifications()` | `testDisabledFeatureDoesNotRegisterRemoteNotificationsWhenAuthorized` が authorized status でも registrar call count 0 を検証 | `xcodebuild ... -only-testing:FeedmanTests/NotificationPermissionCoordinatorTests test` 成功 | 実 `UIApplication.shared.registerForRemoteNotifications()` は呼ばず recording registrar で検証 |
| 3.7 | `NotificationPermissionCoordinator` initializer default `.nextPhaseEnabled` | Enabled permission request flow | `testNotDeterminedPermissionRequestsAuthorizationAndRegistersWhenGranted`, `testExistingAuthorizedPermissionRegistersWithoutPromptingAgain` が enabled default の registrar call count 1 を維持 | 同上 成功 | APNs device registration service enabled coverage は task 2 で維持済み |
| 5.2 | `AppEnvironment.production(notificationFeatures:)` が coordinator に feature flag を渡し、coordinator が disabled 時に registrar の手前で短絡 | Production default permission coordinator boundary | `testDisabledFeatureDoesNotRegisterRemoteNotificationsWhenAuthorized` と production wiring diff で disabled no-remote-registration path を確認 | 同上 成功 / `git diff --check` 成功 | production coordinator の実 UNUserNotificationCenter は unit test で直接叩かない |
| 5.3 | `.nextPhaseEnabled` default と existing tests | Enabled configuration unit coverage | 既存 `NotificationPermissionCoordinatorTests` 4 件が authorization status handling と failure path を維持 | 同上 成功 | next phase repository / ViewModel coverage の最終確認は task 5 scope |

#### Finding Closure Matrix

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| N/A | Reviewer | 対応不要 | N/A | N/A | `review-notes.md` round 1 は `RESULT: approve` / Findings なし | task 3 着手前の review は task 2 approve のため corrective commit 不要 |

#### Verification

- Red 確認: `testDisabledFeatureDoesNotRegisterRemoteNotificationsWhenAuthorized` 追加直後の targeted `xcodebuild ... test` は `notificationFeatures` initializer 未実装により compile failure（期待どおり）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/NotificationPermissionCoordinatorTests test`: 成功
- `git diff --check`: 成功

STATUS: complete
