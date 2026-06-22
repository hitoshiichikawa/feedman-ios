# Issue #54 APNs device registration foundation 実装ノート

## 実装概要

- `Feedman/Core/DeviceRegistrationRepository.swift` を追加し、`POST /api/devices` と `DELETE /api/devices/{id}` を既存 `APIClient` 経由で呼ぶ repository 境界を追加した。
- `DeviceRegistrationRequest` / `DeviceRegistrationResponse` を `APIModels.swift` に追加し、登録 request は `platform: "ios"` と `push_token` を送る形にした。
- `Feedman/Features/Notifications/NotificationPermissionCoordinator.swift` を追加し、`UNUserNotificationCenter` を隠す protocol 境界で現在の許可状態確認、必要時の許可要求、許可済み時の `registerForRemoteNotifications()` 呼び出しを分離した。
- `Feedman/Features/Notifications/APNsDeviceRegistrationService.swift` を追加し、APNs device token `Data` の lowercase hex 変換、未認証時の pending 化、同一 token の in-flight 重複抑止、登録成功時の device id 保存、ログアウト時の登録解除を集約した。
- `FeedmanAppDelegate` を追加し、`UIApplicationDelegateAdaptor` で APNs token 成功/失敗 callback を service bridge に渡すようにした。
- `AppEnvironment` に notification permission coordinator と device registration service を注入し、login / session restore 後の pending token retry、logout 時の best-effort unregister、退会後の local state clear を接続した。
- Account 画面の logout placeholder を実 logout completion に接続し、ログアウト中 / 失敗時の UI state を追加した。

## テスト

- `DeviceRegistrationRepositoryTests`
  - `POST /api/devices` の method / path / Bearer / JSON body を検証。
  - `DELETE /api/devices/{id}` の method / path / Bearer を検証。
  - 登録 API の 401 refresh retry を既存 `APIClient` に委譲することを検証。
- `NotificationPermissionCoordinatorTests`
  - `notDetermined` では許可要求後、許可済みなら remote notification registration を呼ぶことを検証。
  - `denied` では再要求せず `/api/devices` 登録前段へ進まないことを検証。
  - `provisional` など既存許可済み状態では再 prompt せず registration を呼ぶことを検証。
  - 許可要求失敗時に registration を呼ばないことを検証。
- `APNsDeviceRegistrationServiceTests`
  - APNs token の lowercase hex 変換を検証。
  - 未認証時の登録 defer、認証済み時の登録と device id 保存、同一 token in-flight 重複抑止、失敗後 retry、logout unregister と local state clear を検証。
- `AppEnvironmentLogoutTests`
  - 既知 device id がある logout で unregister、auth revoke、local state clear、未認証遷移を検証。
  - device id がない場合は unregister せず logout を継続することを検証。
  - unregister 失敗時も local logout を継続し、失敗結果を返すことを検証。
- `AccountViewModelTests` / `AppEnvironmentSessionRestoreTests`
  - logout completion 接続と退会時 local device state clear を既存テストに追加。

## 検証結果

```bash
plutil -lint Feedman.xcodeproj/project.pbxproj
git diff --check
```

- 成功。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- 成功。405 tests, 0 failures。
- `xcode-select` の active developer directory は `/Library/Developer/CommandLineTools` のままだったため、ローカル検証では `DEVELOPER_DIR` で `/Applications/Xcode.app` を指定した。

## 確認事項

- `POST /api/devices` の成功 response shape は仕様に未記載。本実装は `{"id":"..."}` を device unregister 用 identifier として受け取る前提にした。
- `DELETE /api/devices/{id}` の成功 status / body は仕様に未記載。本実装は既存 `sendNoContent` の扱いに合わせ、2xx を成功として扱う。
- ログアウト時の unregister 失敗は best-effort とし、local logout は継続する。失敗は `AppLogoutResult.deviceUnregisterResult` でテスト可能にしている。
- APNs token の canonical string は lowercase hexadecimal とした。サーバー側が別形式を要求する場合は `APNsDeviceTokenFormatter` を調整する。
- 通知許可要求の常設 UI 導線は未実装。今 Issue は foundation のみで、keyword notification drawer / sheet はスコープ外。
- 許可要求 option は `.alert` と `.sound` にした。`.badge` が必要かは後続の通知 UI / product 判断で確認する。

## Reviewer reject 是正

- `AppEnvironment` に `pendingDeviceRegistrationRetryError` を追加し、`completeLogin(with:)` と `restoreSessionAtLaunch()` からの pending APNs device registration retry 失敗を握りつぶさず、owning flow が観測できる retryable error state として保持するようにした。
- pending retry 成功時、logout、退会後 local clear、session restore 失敗時は `pendingDeviceRegistrationRetryError` を clear し、古い retry error が残らないようにした。
- `AppEnvironmentSessionRestoreTests` に login 後 retry と session restore 後 retry の失敗ケースを追加し、retry 失敗が `AppEnvironment` から観測できること、失敗後も `APNsDeviceRegistrationService` が APNs token を保持して同じ token で再 retry できることを検証した。

## Reviewer reject 是正 2

- `APNsDeviceRegistrationError.remoteNotificationRegistrationFailed` を追加し、APNs remote notification registration failure callback を raw `Error` の保存ではなく Notifications feature の domain error に変換するようにした。
- `APNsDeviceRegistrationBridge` から MainActor closure で `AppEnvironment.apnsRegistrationError` へ通知し、`didFailToRegisterForRemoteNotificationsWithError` 相当の失敗を owning flow から観測可能にした。APNs device token 成功 callback では古い APNs registration failure state を clear する。
- logout、退会後 local clear、session restore failure、APNs device token 成功 callback 時に `apnsRegistrationError` を clear し、`pendingDeviceRegistrationRetryError` は `/api/devices` retry 専用 state のまま分離した。
- `AppEnvironmentSessionRestoreTests` に APNs registration failure が `/api/devices` mock を呼ばず domain error を publish するケースと、成功 token callback 後に古い APNs registration failure state が clear されるケースを追加した。

## Reviewer reject 是正 3

- `APNsDeviceRegistrationBridge.handleDeviceToken(_:)` からの `/api/devices` 登録失敗を `AppEnvironment.pendingDeviceRegistrationRetryError` に publish するようにし、APNs token 取得失敗用の `apnsRegistrationError` と device 登録 retry 用 state を分離したまま owning flow から観測可能にした。
- APNs device token callback での登録成功時は `pendingDeviceRegistrationRetryError` も clear し、古い retry error が成功後に残らないようにした。
- `AppEnvironmentSessionRestoreTests` に認証済み APNs token callback で `/api/devices` が失敗する本番経路のテストを追加し、local registered state が作られないこと、同じ token で再登録できること、成功後に retry error が clear されることを検証した。
- actor mock の request 配列 assertion は `XCTAssertEqual(await actor.property, ...)` ではなく、先に local 変数へ取り出す形へ揃え、Swift の autoclosure と `await` の衝突でテスト target がビルド失敗しないようにした。
