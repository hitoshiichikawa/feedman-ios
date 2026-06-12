# Issue #23 APIClient 401 refresh retry hook 要件定義

## 概要

Issue #23 は Parent: #2 の子 Issue として、認証必須 API が `401` を返したときに `APIClient` が access token refresh を 1 回だけ試行し、成功した場合に元 request を 1 回だけ再送する hook を追加する。

`design/SPEC-iOS.md` では、アクセストークンを全 API に `Authorization: Bearer <access_token>` として付与し、`401` を検知したら `refresh` → retry を `APIClient` で透過処理すると定義されている。`design/SERVER.md` では `POST /api/auth/refresh` が refresh token rotation 付きで新しい access token / refresh token を返し、拒否時は `401 INVALID_REFRESH_TOKEN` を返すと定義されている。

依存状態は以下のとおり確認済み。

- #16 `APIClient base request and JSON handling`: PR #65 が develop へ merge 済み。Issue は multi-branch 運用により `OPEN` / `codex-staged-for-release`。
- #20 `AuthRepository token refresh and revoke`: PR #74 が develop へ merge 済み。Issue は multi-branch 運用により `OPEN` / `codex-staged-for-release`。

Issue #23 のコメントでは、依存 #16/#20 は develop merge 済みとして `codex-blocked` が除去され、`codex-auto-dev` が付与されている。Path Overlap Checker の edit path は `Feedman/` と `FeedmanTests/` である。#21 と同時投入のため、pbxproj など hot file で競合する場合は Path Overlap Checker に従う。

## スコープ

- 既存 `APIClient` の request construction / JSON decode / typed error mapping を保ったまま、認証付き request の `401` に対する refresh retry hook を追加する。
- refresh hook は `AuthRepository` または同等の refresh abstraction を通じて access token refresh を実行する。
- refresh 成功後は、新しい access token を付与して元 request を 1 回だけ retry する。
- refresh 失敗時は無限 retry せず、呼び出し側がログイン要求へ遷移できる typed auth-required error を surface する。
- Unit test では mock transport と mock refresh hook / mock AuthRepository を使い、実サーバー、実 OAuth、実 Keychain に依存せずに 401 retry の分岐を検証する。

## スコープ外

- Google login UI、`ASWebAuthenticationSession`、OAuth callback handling。
- `/api/auth/token`、`/api/auth/refresh`、`/api/auth/revoke` の concrete `AuthRepository` 実装自体。
- `TokenStore` / Keychain の保存・削除ロジック変更。
- endpoint-specific repository、Feature ViewModel、SwiftUI 画面、logout 画面遷移の実装。
- refresh token rotation のサーバー仕様変更、再利用検知の詳細 UI、サーバー側 API 変更。
- `401` 以外の HTTP error に対する retry policy。
- 事前 expiry 判定による proactive refresh。今回は response `401` を契機にした retry hook に限定する。

## 要件

### Requirement 1: 401 detection for authenticated requests

**Objective:** As a Repository 実装者, I want 認証付き API 呼び出しで `401` を共通検知できる, so that 各 endpoint repository が refresh/retry 分岐を重複実装しなくて済む

#### Acceptance Criteria

1. When an authenticated request receives an HTTP `401` response, the APIClient shall treat it as a candidate for access-token refresh before surfacing the original `401` to the caller.
2. When an unauthenticated request receives an HTTP `401` response, the APIClient shall not call refresh and shall surface the typed Feedman API error through the existing response decoding path.
3. When an authenticated request receives a non-`401` non-2xx response, the APIClient shall not call refresh and shall preserve the existing `FeedmanAPIError.feedmanError` / malformed error mapping behavior.
4. When an authenticated request succeeds with a 2xx response, the APIClient shall not call refresh.
5. The APIClient shall preserve the existing `APIResponseDecoder` contract for success decode and non-refreshable failure mapping.

### Requirement 2: Refresh hook invocation

**Objective:** As an Auth 実装者, I want APIClient が 401 時に AuthRepository refresh を 1 回だけ呼ぶ, so that access token lifecycle を AuthRepository / TokenStore 側に集約できる

#### Acceptance Criteria

1. When an authenticated request receives `401`, the APIClient shall call the configured AuthRepository refresh hook once.
2. When multiple retry attempts would be possible for the same original request, the APIClient shall not call refresh more than once for that original request.
3. If no refresh hook / AuthRepository is configured for an authenticated request that receives `401`, the APIClient shall fail with an auth-required typed error rather than silently retrying or crashing.
4. The refresh hook shall return the latest access token needed to rebuild the `Authorization: Bearer <access_token>` header for the retry.
5. The refresh hook shall be responsible for refresh token rotation and TokenStore update; the APIClient shall not directly read or write Keychain.
6. The APIClient shall not call `/api/auth/refresh` directly unless that responsibility is provided by the AuthRepository abstraction from #20.

### Requirement 3: Original request retry after refresh success

**Objective:** As an app user, I want an expired access token to be recovered transparently, so that the original operation succeeds without a visible login interruption when refresh is valid

#### Acceptance Criteria

1. When refresh succeeds after an authenticated request receives `401`, the APIClient shall retry the original request once with the refreshed access token.
2. When retrying the original request, the APIClient shall preserve the original HTTP method, path, query items, JSON body, and headers other than replacing the `Authorization` bearer value with the refreshed token.
3. When the retried request returns 2xx valid JSON, the APIClient shall decode and return the retried response as the original requested `Decodable` type.
4. When the retried request returns a non-2xx response, the APIClient shall surface that retried response through the existing typed error mapping and shall not perform another refresh for the same original request.
5. When the retried request returns `401`, the APIClient shall surface an auth-required typed error or the retried `401` in a way that callers can distinguish from ordinary validation/server errors and shall not enter an infinite retry loop.
6. The APIClient shall not expose the intermediate first `401` as a failure to callers when refresh and retry both succeed.

### Requirement 4: Refresh failure and auth-required error

**Objective:** As a ViewModel 実装者, I want refresh 失敗を login-required 状態として判別できる, so that UI can route to logout/login without mistaking it for endpoint validation failure

#### Acceptance Criteria

1. When refresh fails because the refresh token is missing, expired, invalid, revoked, or rejected by the server, the APIClient shall surface a typed auth-required error.
2. When refresh fails with server `401 INVALID_REFRESH_TOKEN`, the APIClient shall not retry the original request.
3. When refresh fails with transport or malformed response failure, the APIClient shall not retry the original request and shall preserve enough underlying error context for debugging.
4. When refresh fails, the APIClient shall not clear credentials directly unless that behavior belongs to the #20 AuthRepository contract; credential clearing shall remain outside the APIClient transport layer.
5. The typed auth-required error shall be distinguishable from `FeedmanAPIError.feedmanError` for ordinary endpoint failures such as validation, cooldown, or not found.
6. The error surface shall avoid storing or logging access token / refresh token values.

### Requirement 5: Concurrency and duplicate refresh control

**Objective:** As a Developer, I want concurrent 401 responses to avoid unsafe refresh token reuse, so that refresh token rotation is not broken by parallel duplicate refresh calls

#### Acceptance Criteria

1. When two or more authenticated requests receive `401` concurrently, the APIClient/Auth refresh boundary shall avoid issuing multiple simultaneous refresh calls with the same refresh token.
2. While a refresh is already in progress, subsequent authenticated requests that need refresh shall await the in-flight refresh result or otherwise use a serialized AuthRepository refresh mechanism.
3. When the shared in-flight refresh succeeds, waiting requests shall retry with the refreshed access token and shall not each trigger their own refresh.
4. When the shared in-flight refresh fails, waiting requests shall fail with auth-required or the same typed refresh failure category and shall not retry the original requests.
5. Where duplicate refresh suppression is already guaranteed by #20 AuthRepository, the APIClient shall rely on that contract instead of reimplementing token rotation logic.
6. The implementation shall document in `impl-notes.md` whether duplicate refresh suppression is implemented in APIClient or delegated to AuthRepository.

### Requirement 6: APIClient integration boundary

**Objective:** As a Core module maintainer, I want refresh retry support to fit the existing APIClient shape, so that #16 request/decode behavior remains stable

#### Acceptance Criteria

1. The APIClient shall continue to support unauthenticated requests for token exchange and public auth endpoints.
2. The APIClient shall continue to support authenticated requests that pass an explicit access token or an injected token provider, as long as the refresh hook can supply a refreshed token for retry.
3. The APIClient shall remain mockable through `APITransport` or equivalent test transport.
4. The APIClient shall not make SwiftUI View or ViewModel depend directly on `URLSession`, Keychain, or refresh token storage.
5. The APIClient shall keep request body encoding deterministic enough that a JSON body can be reused for a single retry without requiring the caller to rebuild side-effectful state.
6. The implementation shall keep changes under `Feedman/Core` and test support under `FeedmanTests` unless the actual #20 AuthRepository files require adjacent updates.

### Requirement 7: Unit test coverage

**Objective:** As a QA/Developer, I want refresh retry behavior fixed by focused XCTest coverage, so that future repository work can rely on a stable auth transport contract

#### Acceptance Criteria

1. When an authenticated request first returns `401` and refresh succeeds, the test suite shall verify that the transport receives exactly two original endpoint requests and one refresh hook call.
2. When refresh succeeds, the test suite shall verify that the retried original request uses `Authorization: Bearer <refreshed_access_token>`.
3. When the retried original request succeeds, the test suite shall verify that the caller receives the decoded retried response.
4. When refresh fails, the test suite shall verify that the original endpoint is not retried and an auth-required typed error is surfaced.
5. When the retried original request returns `401`, the test suite shall verify that refresh is not called a second time for the same original request.
6. When an unauthenticated request returns `401`, the test suite shall verify that refresh is not called.
7. When a non-`401` error such as `400` or `429 FEED_COOLDOWN` is returned, the test suite shall verify that refresh is not called and existing typed error metadata is preserved.
8. When two authenticated requests receive `401` concurrently, the test suite shall verify the chosen duplicate refresh suppression behavior or the AuthRepository delegation contract.
9. Unit tests shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
10. While macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and use Swift Concurrency compatible APIs.
2. The implementation shall preserve #16 APIClient base request construction, JSON handling, `APITransport` mockability, and `APIResponseDecoder` typed error behavior.
3. The implementation shall preserve #20 AuthRepository responsibility for token exchange / refresh rotation / revoke / TokenStore update.
4. The implementation shall keep `API` / `Auth` shared code under `Feedman/Core` according to the project architecture.
5. The implementation shall not introduce real secrets, real tokens, or personal information into source code, tests, fixtures, logs, or documentation.

### NFR 2: Scope control

1. The implementation shall be limited to the APIClient 401 refresh retry hook, required auth abstraction wiring, and focused unit tests.
2. The implementation shall not add login UI, app shell routing, endpoint-specific repositories, feature ViewModels, or SwiftUI screens.
3. The implementation shall not change server API contracts from `design/SPEC-iOS.md` / `design/SERVER.md`.
4. The implementation shall not modify finalized `docs/specs/*` from other Issues unless explicitly required by a dependency mismatch and called out in notes.
5. The implementation shall not create PRs, invoke reviewer/project-manager agents, or perform release operations as part of Stage A.

## 実装境界

- `APIClient` は `401` retry orchestration を担当するが、refresh token の読み書き、rotation 成功時の保存、revoke、credential clear の責務は `AuthRepository` / `TokenStore` 側に残す。
- refresh hook の具体的な型は #20 の実装に合わせる。PM 要件としては「`401` 時に 1 回 refresh し、新しい access token で元 request を 1 回 retry できる」ことを固定する。
- `401` の initial response body は、refresh 成功時には caller に露出しない。refresh 失敗時や retry 後 `401` では、caller が login-required と判別できる typed error を surface する。
- retry は idempotent method だけに限定しない。`PUT /api/items/{id}/state` や `POST /api/subscriptions/{id}/fetch` など v1 の認証必須操作でも、サーバーが最初の `401` では business action を実行していない前提で 1 回 retry できる。
- request body は retry のために再利用可能な `Data` として保持する。streaming body や一度しか読めない body は本 Issue の対象外とする。

## 確認事項

- Developer 開始前に最新 `origin/develop` を fast-forward し、#20 の `Feedman/Core/Auth/AuthRepository.swift` と `docs/specs/20-authrepository-token-refresh-and-revoke/` が存在することを確認済み。refresh hook は #20 の `AuthRepository.refreshTokens()` が返す `TokenCredentials.accessToken` を利用する。
- auth-required typed error は `FeedmanAPIError` に追加し、refresh hook 未設定、refresh 失敗、retry 後の再 `401` を caller が通常の endpoint validation/server error と区別できるようにする。
- #20 の `FeedmanAuthRepository.refreshTokens()` は単体では並列 refresh 抑止を持たないため、本 Issue では APIClient 側の refresh hook boundary で同一 `APIClient` インスタンス内の in-flight refresh を共有する。
