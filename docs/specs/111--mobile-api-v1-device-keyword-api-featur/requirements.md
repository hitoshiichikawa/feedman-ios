# Requirements Document

## Introduction

Issue #111 は、iOS v1 でスコープ外とされているキーワードプッシュ通知の導線を feature gate し、production default で `/api/devices` と `/api/keywords` に到達しない状態へ戻すための要件である。

`design/SPEC-iOS.md` と `design/SERVER.md` では、キーワードプッシュ通知、APNs device registration、`/api/devices`、`/api/keywords` は次フェーズ扱いであり、v1 の smoke checklist には含めない。一方、現在の iOS `develop` には APNs device registration foundation、Keyword repository、Keyword settings UI、通知 deep link foundation が存在するため、v1 サーバーに未実装の next phase API を呼んで 404 を踏む可能性がある。

Issue コメントでは追加の仕様決定はなく、Path Overlap Checker による想定 edit paths は `Feedman/`、`FeedmanTests/`、`README.md` である。関連サーバ契約として `hitoshiichikawa/feedman#207` が挙げられているが、本 Issue ではサーバー API 契約を変更せず、iOS 側の既定挙動を v1 scope に合わせる。

## Requirements

### Requirement 1: v1 default feature gate

**Objective:** As a Release Owner, I want v1 production default でキーワード通知関連機能を無効化できる, so that v1 サーバーが未実装の device / keyword API を受けない

#### Acceptance Criteria

1. When `AppEnvironment.production()` is created with default arguments, the app shall configure keyword notification related behavior as disabled.
2. When keyword notification behavior is disabled, the app shall not construct the active production path with `APIClientDeviceRegistrationRepository` as the runtime device registration dependency.
3. When keyword notification behavior is disabled, the app shall not construct the active production path with `APIClientKeywordRepository` as the runtime keyword settings dependency.
4. When keyword notification behavior is enabled explicitly, the app shall be able to use the existing real device registration and keyword repository implementations.
5. The implementation shall keep the feature gate value injectable for tests and previews without reading remote configuration or adding a server dependency.

### Requirement 2: Keyword settings UI route gating

**Objective:** As a v1 user, I want v1 default の drawer にキーワード通知導線が表示されない, so that 未提供機能を開いて `/api/keywords` エラーに遭遇しない

#### Acceptance Criteria

1. When keyword notification behavior is disabled, the drawer shall not display the keyword settings entry point.
2. When keyword notification behavior is disabled, the app shall not present `KeywordSettingsSheet` through normal AppShell user interaction.
3. When keyword notification behavior is disabled, no `KeywordSettingsViewModel` load or mutation shall be started by the AppShell.
4. When keyword notification behavior is enabled explicitly, the existing keyword settings sheet flow shall remain reachable.
5. If a disabled keyword settings presentation is requested defensively, the app shall avoid calling `/api/keywords` and shall recover without crashing.

### Requirement 3: APNs device registration API suppression

**Objective:** As a v1 server operator, I want disabled 状態で APNs token registration 系が `/api/devices` を呼ばない, so that v1 API surface と未実装 next phase API が混在しない

#### Acceptance Criteria

1. When keyword notification behavior is disabled, APNs device token callbacks shall not call `POST /api/devices`.
2. When keyword notification behavior is disabled, remote notification registration shall not be requested from the notification permission coordinator.
3. When keyword notification behavior is disabled and login completes, pending device registration retry shall not call `POST /api/devices`.
4. When keyword notification behavior is disabled and session restoration succeeds, pending device registration retry shall not call `POST /api/devices`.
5. When keyword notification behavior is disabled and logout occurs, remote device unregister shall not call `DELETE /api/devices/{id}`.
6. When keyword notification behavior is disabled, local stale device registration state may be cleared as cleanup, but the cleanup shall not depend on a successful network call.
7. When keyword notification behavior is enabled explicitly, the existing APNs device registration, retry, and logout unregister behavior shall remain testable.

### Requirement 4: Existing next phase implementation preservation

**Objective:** As a Developer, I want next phase 用 repository / ViewModel / sheet を削除せず隔離する, so that サーバー実装後に feature flag を有効化して再利用できる

#### Acceptance Criteria

1. The implementation shall keep `APIClientDeviceRegistrationRepository` and its request contract tests.
2. The implementation shall keep `APIClientKeywordRepository` and its request contract tests.
3. The implementation shall keep `KeywordSettingsViewModel` behavior tests for enabled-path loading and mutations.
4. The implementation shall keep `KeywordSettingsSheet` available for enabled-path integration.
5. The implementation shall avoid broad refactors of notification deep link article navigation unless required to prevent `/api/devices` or `/api/keywords` calls.

### Requirement 5: v1 smoke checklist and verification

**Objective:** As a QA reviewer, I want v1 smoke checklist が next phase API を対象外として明示する, so that 手動検証で `/api/devices` と `/api/keywords` の成功を v1 条件にしない

#### Acceptance Criteria

1. The v1 smoke checklist shall state that `/api/devices` and `/api/keywords` are out of scope for v1 default.
2. When the default production configuration is tested, the test suite shall verify that device registration and keyword repository API calls are not triggered.
3. When the enabled configuration is tested, the test suite shall preserve enough existing unit coverage to prove the next phase path still works.
4. When verification runs on macOS/Xcode, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` shall pass.

## Non-Functional Requirements

### NFR 1: Scope control

1. The implementation shall not remove next phase source files solely because the v1 default disables them.
2. The implementation shall not add new server endpoints or change `design/SPEC-iOS.md` / `design/SERVER.md`.
3. The implementation shall not add keyword notification drawer routes, notification category actions, push worker behavior, OPML import/export, or feed-scoped search UI as part of this Issue.
4. The implementation shall keep View code free from direct `URLSession`, Keychain, APNs token persistence, and raw feature flag storage details.

### NFR 2: Reliability and security

1. While keyword notification behavior is disabled, APNs token, Bearer token, refresh token, keyword term, and personal article data shall not be logged as part of disabled-path handling.
2. While keyword notification behavior is disabled, stale local device registration state cleanup shall be best-effort and shall not block logout or account deletion flows.
3. When tests cover disabled behavior, they shall use mocks or recording repositories and shall not depend on real APNs, real network, real Keychain, or real OAuth.
4. The implementation shall follow iOS 16+、SwiftUI、Swift Concurrency、MVVM + Repository 方針。

## Out of Scope

- サーバー側 `/api/devices` / `/api/keywords` の実装または契約変更。
- キーワード push worker、FCM/APNs 配信、キーワード照合、通知 payload 生成。
- Keyword settings UI の削除。
- Notification deep link article routing の再設計。
- Remote config / A/B testing / server-driven feature flag。
- App Store entitlement / provisioning profile / APNs certificate 設定。

## Open Questions

- なし。Issue 本文と既存コメントから、v1 default は disabled、enabled path は既存 next phase 実装を維持する方針で確定できる。
