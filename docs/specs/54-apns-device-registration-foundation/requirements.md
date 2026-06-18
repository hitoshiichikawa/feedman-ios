# Issue #54 APNs device registration foundation 要件定義

## 背景

Issue #54 は Parent: #13 の子 Issue として、キーワードプッシュ通知の次フェーズに入るための iOS 側 foundation を定義する。今回の主眼は、通知許可要求、APNs device token の取得後登録、ログアウト時の端末登録解除を、後続の keyword CRUD や push worker 実装から分離して先に整えることである。

`design/SPEC-iOS.md` では、iOS のプッシュは APNs を使い、サーバーは FCM 経由で APNs 配信を行う方針である。端末登録は `POST /api/devices { platform:"ios", push_token }` と定義され、`push_token` は APNs device token とされている。また、通知許可要求と受信処理は `UNUserNotificationCenter` を使う。

`design/SERVER.md` §2 では、キーワードプッシュ通知は次フェーズの正本として定義されている。`push_devices` は `user_id` と端末 token を紐付け、`POST /api/devices` は既存登録があれば upsert して `enabled=true` に戻す。登録解除は `DELETE /api/devices/{id}` で行う。退会時は `devices / keywords / keyword_notifications` が削除されることがサーバー側の受け入れ基準に含まれる。

Issue コメントでは、`Depends on: #53` が staged-for-release として依存解除済みであることが記録されているため、本要件では実装ブロックとして扱わない。Path Overlap Checker の edit paths は `Feedman/Features/Notifications/` と `Feedman/Core/` である。

## スコープ

- 通知許可状態を確認し、必要なタイミングで `UNUserNotificationCenter` による許可要求を行う foundation。
- 許可済みまたは許可取得後に APNs remote notification registration を開始できる境界。
- APNs device token を API 送信用の文字列表現へ変換する境界。
- APNs device token が取得できたとき、Bearer 認証付きで `POST /api/devices` に `platform:"ios"` と `push_token` を登録する repository / service 境界。
- 登録済み device id または解除に必要な server-side identifier を保持し、ログアウト時に `DELETE /api/devices/{id}` を呼べる状態管理。
- ログアウト flow から端末登録解除を呼び出すための最小接続要件。
- 許可拒否、APNs token 取得失敗、端末登録失敗、登録解除失敗を UI または上位 flow が扱える domain error / state に変換する要件。
- mock と real implementation を差し替えられる protocol 境界と、主要分岐を XCTest で検証できる要件。

## スコープ外

- キーワード CRUD UI / API (`/api/keywords`)。
- サーバー側 push worker、マッチング、FCM/APNs 配信処理。
- 通知タップ後の `feedman://items/{id}` deep link 遷移の完成実装。
- push 通知の受信表示内容、notification category、action button。
- キーワード通知設定 drawer / sheet の本実装。
- OPML、feed-scoped search、WebView Cookie login fallback。
- サーバー側 `/api/devices` の新規実装または契約変更。
- 退会 flow の再設計。退会による server-side devices cleanup はサーバー契約に委ねる。

## API 契約

### `POST /api/devices`

- 用途: 現在のログインユーザーに iOS 端末を登録する。
- 認証: Bearer token 必須。
- Request body:

```json
{
  "platform": "ios",
  "push_token": "<APNs device token>"
}
```

- 挙動: 同一 user / token の既存登録があれば upsert し、`enabled=true` に戻す。
- iOS 側の前提: `push_token` は APNs device token の文字列表現であり、FCM registration token ではない。
- Response: 端末登録解除に必要な device id をアプリが取得できる必要がある。ただし、現行仕様書には response body の厳密な shape が未記載であるため、実装前に確認する。

### `DELETE /api/devices/{id}`

- 用途: 登録済み端末を解除する。
- 認証: Bearer token 必須。
- Path parameter: `{id}` は `POST /api/devices` または既存状態から得た device id。
- 期待挙動: ログアウト時に対象端末の登録を解除し、以後その端末へ当該ユーザーの push が送られない状態にする。
- Response: 成功 status / body は未記載であるため、no-content 成功を扱える API 境界を前提にしつつ実装前に確認する。

## 要件

### Requirement 1: Notification permission foundation

**Objective:** As a Feedman user, I want iOS 標準の通知許可ダイアログで許可可否を選べる, so that Feedman が許可なく push 通知を有効化しない

#### Acceptance Criteria

1. When notification permission is requested, the app shall use `UNUserNotificationCenter` to request notification authorization.
2. When notification permission is requested, the app shall request only notification options required for keyword push notification foundation.
3. When the user grants notification permission, the app shall expose an authorized state that can trigger APNs remote notification registration.
4. When the user denies notification permission, the app shall not attempt `/api/devices` registration for that denied state.
5. When notification authorization status is already determined, the app shall read the current status before deciding whether to request permission again.
6. If notification permission request fails, the app shall surface a retryable domain error without changing local device registration state.

### Requirement 2: APNs token acquisition boundary

**Objective:** As a Developer, I want APNs token 取得と API 登録を分離した境界にする, so that AppDelegate / app lifecycle と repository をテスト可能に保てる

#### Acceptance Criteria

1. When notification permission is authorized, the app shall start APNs remote notification registration through the iOS application lifecycle boundary.
2. When APNs registration succeeds, the app shall receive the APNs device token and convert it to a stable lowercase hexadecimal string or an otherwise server-approved canonical string.
3. When APNs registration fails, the app shall surface a domain error and shall not call `POST /api/devices`.
4. When an APNs token is received while no authenticated session is available, the app shall not call `POST /api/devices` until a valid authenticated session exists.
5. When the same APNs token is received multiple times for the same authenticated user, the app shall avoid unnecessary duplicate in-flight registration requests while still allowing server upsert semantics to recover registration state.

### Requirement 3: Device registration API

**Objective:** As a Feedman user, I want 許可済み端末がサーバーに登録される, so that 後続のキーワード通知がこの端末へ配信できる

#### Acceptance Criteria

1. When an APNs token is available for an authenticated user, the app shall call `POST /api/devices` with JSON body `{ "platform": "ios", "push_token": "<token>" }`.
2. When device registration is requested, the app shall use the existing Bearer-authenticated API client / repository boundary.
3. When device registration succeeds, the app shall persist or otherwise retain the device identifier needed for future `DELETE /api/devices/{id}`.
4. When device registration succeeds through upsert, the app shall treat the device as enabled for the current user.
5. When device registration fails, the app shall keep the APNs token available for retry and surface a retryable error state to the owning flow.
6. If the server returns a typed Feedman error response, the app shall map it through the existing API error decoding / domain error boundary.
7. If the access token is expired, the request shall rely on the existing APIClient 401 refresh retry behavior rather than implementing refresh logic in the Notifications feature.

### Requirement 4: Logout device unregister

**Objective:** As a Feedman user, I want ログアウト後にこの端末が自分の push 登録として残らない, so that 別ユーザーや未認証状態に通知が届かない

#### Acceptance Criteria

1. When logout occurs and a registered device id is known, the app shall call `DELETE /api/devices/{id}` before or as part of the authenticated logout sequence.
2. When device unregister succeeds, the app shall clear the locally retained device registration identifier for that user.
3. When device unregister succeeds, the app shall continue the existing logout flow for refresh token revoke, Cookie logout if present, local credential clear, and login transition according to the established Account/Auth requirements.
4. If no registered device id is known, the app shall not block logout on device unregister and shall clear any stale local device registration state.
5. If device unregister fails during logout, the app shall not leave the user indefinitely stuck in an authenticated UI; the exact retry / best-effort policy is an implementation decision that must be explicit and must not silently ignore the error in tests.
6. When logout completes locally, the app shall not keep a device registration id associated with the cleared credentials.

### Requirement 5: Feature boundaries and tests

**Objective:** As a Developer, I want 通知 permission / APNs token / device API が protocol 境界で分離される, so that 実 APNs や実ネットワークなしで検証できる

#### Acceptance Criteria

1. When notification foundation is introduced, the app shall define protocol boundaries for notification authorization, APNs token handling, and device registration repository.
2. When tests are added, the test suite shall use mocks for `UNUserNotificationCenter`, APNs token delivery, API transport, and auth/session state.
3. When permission success is tested, the test suite shall verify that authorized state can lead to APNs registration.
4. When permission denial is tested, the test suite shall verify that `/api/devices` is not called.
5. When APNs token registration is tested, the test suite shall verify method `POST`, path `/api/devices`, Bearer-authenticated boundary, and JSON body `platform=ios` / `push_token=<token>`.
6. When logout unregister is tested, the test suite shall verify method `DELETE`, path `/api/devices/{id}`, local device id clearing, and interaction with logout state.
7. While running on simulator or test environment without real APNs token delivery, the implementation shall keep unit tests independent of real Apple push infrastructure.

## 受入基準（EARS）

- When notification permission is requested, the app shall use `UNUserNotificationCenter`.
- When notification permission is denied, the app shall not register a device with `/api/devices`.
- When APNs token is available for an authenticated user, the app shall register it with `platform=ios`.
- When APNs token registration succeeds, the app shall retain the device identifier required for future unregister.
- When APNs token registration fails, the app shall expose a retryable error and shall not mark the device as registered.
- When logout occurs and a registered device id is known, the app shall unregister the device with `DELETE /api/devices/{id}`.
- When logout completes locally, the app shall clear locally retained device registration state.
- If no authenticated session exists, the app shall not call authenticated `/api/devices` endpoints.
- If `/api/devices` returns an auth error, the app shall rely on existing auth/session loss handling and shall not implement a separate token refresh path in Notifications.
- The implementation shall not add keyword CRUD, server push worker behavior, or keyword notification drawer UI in this Issue.

## 非機能・境界条件

- The implementation shall follow iOS 16+、SwiftUI、Swift Concurrency、MVVM + Repository 方針。
- The implementation shall keep View code free from direct `URLSession`, Keychain, and raw APNs token persistence details.
- The implementation shall keep API types / API client / repository protocol in `Feedman/Core` where they are shared contracts, and feature coordination in `Feedman/Features/Notifications`.
- The implementation shall not log APNs token、Bearer token、refresh token、個人情報。
- The implementation shall avoid storing APNs token in a way that survives logout without being associated to a specific authenticated user.
- The implementation shall handle simulator / APNs unavailable environments without crashing.
- The implementation shall treat notification permission denied / provisional / notDetermined / authorized / ephemeral など iOS の authorization status を明示的に扱う。
- The implementation shall be idempotent for repeated APNs token callbacks and repeated logout attempts.
- The implementation shall prefer best-effort cleanup on logout only if the behavior is documented in implementation notes and covered by tests.
- The implementation shall keep `docs/specs/*` の確定済み仕様を実装 PR で勝手に変更しない。
- Swift の型名、識別子、ファイル名は English にする。
- docs/specs 記述は日本語とし、EARS の `When` / `If` / `While` / `Where` / `shall` は英語固定にする。

## 未確認事項

- `POST /api/devices` の成功 response shape が未記載である。`DELETE /api/devices/{id}` に必要な device id をどの response field から得るか、実装前に確認する必要がある。
- `DELETE /api/devices/{id}` の成功 status が 204 No Content 固定か、JSON body を返すかは未記載である。
- ログアウト時に device unregister が失敗した場合、logout を止めるか、best-effort として local logout を進めるかの最終方針は未確定である。要件上は無限に authenticated UI へ閉じ込めないこと、かつ失敗をテストで可視化することを必須とする。
- APNs token の canonical string 形式は仕様に明記がない。一般的な lowercase hexadecimal を候補とするが、サーバー側の期待形式を確認する必要がある。
- 通知許可要求をどの UI action から開始するかは未確定である。本 Issue は foundation を対象とし、キーワード通知設定 UI の常設導線はスコープ外とする。
- iOS authorization option に `.alert` / `.sound` / `.badge` のどれを含めるかは未確定である。キーワード通知の最小要件に合わせて実装前に決める。
- 通知タップ deep link (`feedman://items/{id}`) の routing 完成は後続 Issue の責務とし、本 Issue では受信処理の完成条件に含めない。
