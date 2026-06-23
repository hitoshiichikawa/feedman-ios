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
