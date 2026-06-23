# Implementation Plan

- [x] 1. Production default の notification feature flag と dependency wiring を追加する (P)
  - `NotificationFeatureFlags` を `AppEnvironment` が保持する value として追加し、`AppEnvironment.production()` の default を v1 disabled にする。
  - 明示 enabled 引数では既存 `APIClientDeviceRegistrationRepository` / `APIClientKeywordRepository` / permission coordinator を使う dependency graph を維持する。
  - `AppEnvironment.production()` default が disabled flags と disabled keyword repository を持つこと、enabled configuration が existing API repositories を使えることを unit test で確認する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 5.2_
  - _Boundary: NotificationFeatureFlags, AppEnvironmentNotificationGate, DisabledPathRegressionTests_

- [x] 2. APNs device registration service を disabled 時 no-network にする
  - `APNsDeviceRegistrationService` に feature gate を注入し、disabled 時の token registration / pending retry / logout unregister を repository call なしで short-circuit する。
  - Disabled logout / account deletion cleanup では stale local `DeviceRegistrationState` を clear し、network 成功に依存せず auth state transition を block しない。
  - `APNsDeviceRegistrationServiceTests` と `AppEnvironmentSessionRestoreTests` / `AppEnvironmentLogoutTests` に disabled token callback、login retry、session restore retry、logout unregister が recording repository を呼ばない regression test を追加する。
  - Enabled configuration の既存 registration / retry / unregister tests は必要に応じて feature flag enabled を渡して維持する。
  - _Requirements: 3.1, 3.3, 3.4, 3.5, 3.6, 3.7, 5.2, 5.3_
  - _Boundary: APNsDeviceRegistrationServiceGate, AppEnvironmentNotificationGate, DisabledPathRegressionTests_
  - _Depends: 1_

- [x] 3. Notification permission から remote notification registration を disabled 時に起動しない
  - Disabled production wiring で `UIApplication.shared.registerForRemoteNotifications()` に到達しない構成にする。
  - Coordinator gate または unavailable registrar injection のどちらかを採用し、enabled path の authorization status handling は維持する。
  - `NotificationPermissionCoordinatorTests` に disabled 時は authorization が許可相当でも remote registrar call count が 0 である test を追加し、enabled 既存 tests は維持する。
  - _Requirements: 3.2, 3.7, 5.2, 5.3_
  - _Boundary: NotificationPermissionCoordinator, DisabledPathRegressionTests_
  - _Depends: 1_

- [x] 4. Keyword settings の drawer 導線と repository 誤到達を feature gate する
  - `RootView` / `DrawerView` で disabled 時に「キーワード通知」footer action を表示しない。
  - Disabled 時に `KeywordSettingsSheet` と `KeywordSettingsViewModel.loadKeywords()` が AppShell の通常操作から開始されないようにする。
  - `DisabledKeywordRepository` を追加し、防御的に keyword repository method が呼ばれても `/api/keywords` へ到達しないようにする。
  - AppShell state/helper tests または repository tests で disabled presentation 防御と disabled keyword repository no-network behavior を確認する。
  - Enabled configuration では既存 keyword settings sheet flow が引き続き reachable であることを既存 tests の更新で確認する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 5.2, 5.3_
  - _Boundary: KeywordSettingsRouteGate, DisabledKeywordRepository, DisabledPathRegressionTests_
  - _Depends: 1_

- [x] 5. Next phase enabled path の既存 repository / ViewModel / sheet coverage を維持する
  - `APIClientDeviceRegistrationRepository` の POST/DELETE path、Bearer header、refresh retry tests を削らずに通す。
  - `APIClientKeywordRepository` の GET/POST/PATCH/DELETE path、Bearer header、refresh retry tests を削らずに通す。
  - `KeywordSettingsViewModelTests` の loading / mutation / error mapping coverage を enabled path として維持する。
  - `KeywordSettingsSheet` と notification article deep link source は削除せず、今回の差分が `/api/devices` / `/api/keywords` 抑止の範囲を超えていないことを差分レビューする。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 5.3_
  - _Boundary: ExistingNextPhaseComponents, APNsDeviceRegistrationServiceGate, DisabledKeywordRepository, KeywordSettingsRouteGate_
  - _Depends: 2, 4_

- [x] 6. v1 smoke checklist と最終検証を更新する
  - `README.md` の v1 Smoke Test Checklist に `/api/devices` と `/api/keywords` は v1 default では対象外であり、keyword notification feature が disabled であることを明記する。
  - `plutil -lint Feedman.xcodeproj/project.pbxproj` と `git diff --check` を実行し、project file / whitespace の基本整合を確認する。
  - macOS/Xcode 環境で `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行する。
  - _Requirements: 5.1, 5.4_
  - _Boundary: V1SmokeChecklist, DisabledPathRegressionTests_
  - _Depends: 1, 2, 3, 4, 5_

## Verify

本 spec の実装後、watcher（stage-a-verify gate）が再実行すべき verify コマンドを構造化ブロックで宣言する。

<!-- stage-a-verify -->
```sh
plutil -lint Feedman.xcodeproj/project.pbxproj &&
git diff --check &&
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
