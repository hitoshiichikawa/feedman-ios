# 要件定義

## 概要

Issue #34 は Parent: #7 の子 Issue として、記事詳細取得と既読 / スター状態更新を行う Repository methods を追加する。
`design/SPEC-iOS.md` と `design/SERVER.md` の API 契約では、記事詳細は `GET /api/items/{id}` で `content` を含む `ItemDetail` を取得し、状態更新は `PUT /api/items/{id}/state` へ `{is_read?, is_starred?}` の partial body を送る。
本 Issue は Repository 層の method、real implementation、mock implementation、単体テスト観点に閉じ、記事詳細 sheet UI、SFSafariViewController 起動、一覧 / 詳細 / スター一覧をまたぐ optimistic sync は扱わない。

Issue 本文の依存 `Depends on: #23` は、Issue コメントで人間により PR #75 として `develop` へ merge 済みであることが確認されている。
これにより #23 の APIClient 401 refresh retry hook を利用できる前提で進める。
Issue コメントにある Phase E の edit_paths は `Feedman/` と `FeedmanTests/` である。

## 参照仕様

- `design/SPEC-iOS.md` §4.2, §4.3, §5.4, §6, §10
- `design/SERVER.md` §1 の Bearer 認証前提と既存 API 互換要件
- Issue #34 本文と `gh issue view 34 --comments` の既存コメント
- 先行 Issue #14 API domain models、#15 typed Feedman error、#16 APIClient、#23 401 refresh retry hook

## スコープ

- `ItemRepository` または同等の repository protocol に、記事詳細取得と記事状態更新の async methods を追加する。
- real repository implementation は `APIClient` を利用し、認証付き request と typed error surface を既存 API layer に委譲する。
- mock repository implementation は後続 ViewModel / UI から差し替え可能な deterministic data と state update behavior を提供する。
- `ItemDetail` と `ItemStateUpdateRequest` など、既存 API model 契約を利用する。
- Repository tests は mock transport / mock repository を使い、実ネットワーク、実 Keychain、実 OAuth に依存しない。

## スコープ外

- 記事詳細 sheet、`.presentationDetents`、本文 HTML rendering、SwiftUI view の実装。
- SFSafariViewController の presenter 実装、外部記事を開く UI、外部記事を開いた後の既読化 orchestration。
- 一覧 / 詳細 / スター一覧 / 検索結果をまたぐ optimistic update、失敗時 rollback、cross-screen state sync。
- 横断タイムライン、フィード別一覧、スター一覧、検索の pagination / list Repository methods。
- Feed-scoped search UI、キーワードプッシュ通知、OPML、オフライン全文 cache。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md`、他 Issue の確定済み `docs/specs/*` の変更。

## 要件

### Requirement 1: Item repository boundary

**Objective:** As a ViewModel 実装者, I want 記事詳細取得と状態更新を Repository protocol 経由で呼べる, so that View が `URLSession`、Keychain、APIClient の request construction を直接扱わずに済む

#### Acceptance Criteria

1. The item repository shall async / await で呼び出せる記事詳細取得 method を提供する。
2. The item repository shall async / await で呼び出せる記事状態更新 method を提供する。
3. The item repository shall `Feedman/Core` 配下の protocol として定義し、Feature View / ViewModel が concrete real implementation へ直接依存しない構成にする。
4. The real item repository shall `APIClient` を利用して HTTP request を構築し、View や ViewModel から `URLSession` を直接触らせない。
5. The mock item repository shall 後続の ArticleDetail / Timeline / Starred / Search などの ViewModel tests で差し替え可能な形にする。
6. The item repository shall API の日付文字列を `Date` へ自動変換せず、既存 API model と同じ RFC3339 `String` として扱う。
7. The item repository shall favicon の `data:` URL または `nil` を画像化せず、既存 API model の nullable `String` として保持する。

### Requirement 2: Item detail fetch

**Objective:** As an ArticleDetail ViewModel 実装者, I want item id から `ItemDetail` を取得できる, so that 詳細 sheet 実装時に `content` を含む記事詳細データを Repository から受け取れる

#### Acceptance Criteria

1. When item detail is requested for an item id, the real item repository shall call `GET /api/items/{id}`.
2. When item detail is requested with an access token, the request shall send `Authorization: Bearer <access_token>` through the existing APIClient authentication path.
3. When the server returns a successful item detail response, the repository shall decode and return `ItemDetail`.
4. When the successful item detail response contains `content`, the repository shall preserve `content` without HTML rendering or sanitizing in this Issue.
5. When the successful item detail response contains `feed_favicon_url`, `published_at`, `hatebu_fetched_at`, `is_read`, or `is_starred`, the repository shall preserve those values according to the existing `ItemDetail` API model.
6. When the APIClient receives an initial `401` for an authenticated detail request, the repository shall rely on the #23 APIClient refresh retry behavior rather than implementing endpoint-specific refresh logic.
7. If detail fetch fails with a Feedman standard error body, the repository shall surface the existing typed `FeedmanAPIError` information without replacing it with an untyped string-only error.
8. If detail fetch fails because authentication cannot be refreshed or is required, the repository shall surface the existing auth-required typed error boundary so the caller can distinguish it from normal endpoint validation errors.

### Requirement 3: Read and star state update

**Objective:** As a Timeline / ArticleDetail ViewModel 実装者, I want 既読とスター状態を partial update できる, so that UI 側の user action を API 契約どおり server state へ反映できる

#### Acceptance Criteria

1. When read state changes, the real item repository shall call `PUT /api/items/{id}/state`.
2. When star state changes, the real item repository shall call `PUT /api/items/{id}/state`.
3. When only read state is requested, the request body shall include `is_read` and shall not force an `is_starred` value.
4. When only star state is requested, the request body shall include `is_starred` and shall not force an `is_read` value.
5. When both read and star state are requested in one repository call, the request body shall include both `is_read` and `is_starred`.
6. When a field is not part of the requested mutation, the repository shall omit that field from the JSON body rather than sending a default `false`.
7. When the state update request succeeds with any 2xx response, the repository shall treat the mutation as successful without requiring an updated item response body.
8. When the state update request fails with a Feedman standard error body, the repository shall surface the existing typed `FeedmanAPIError` information.
9. When the APIClient receives an initial `401` for an authenticated state update request, the repository shall rely on the #23 APIClient refresh retry behavior for the original `PUT` request.
10. The repository shall not perform optimistic UI update, cross-screen state propagation, or rollback orchestration inside this Issue.

### Requirement 4: Mock repository behavior

**Objective:** As a ViewModel test author, I want mock item repository behavior を制御できる, so that UI state tests can cover loading / success / empty / error paths without real network

#### Acceptance Criteria

1. When mock detail data is configured for an item id, the mock item repository shall return the corresponding `ItemDetail`.
2. When mock detail data is not configured for an item id, the mock item repository shall fail deterministically with a testable error or configured failure.
3. When mock state update succeeds, the mock item repository shall record the item id and requested partial state values.
4. When mock state update succeeds for configured in-memory item detail data, the mock may update `is_read` and `is_starred` in that in-memory data to support later ViewModel tests.
5. If mock state update mutates in-memory data, it shall only mutate fields explicitly present in the partial update request.
6. When mock state update is configured to fail, the mock item repository shall surface the configured error and shall not silently mark the mutation as successful.
7. The mock item repository shall not depend on real Keychain, real OAuth, real APIClient, or real network.

### Requirement 5: Test coverage

**Objective:** As a QA / Developer, I want Repository request construction と error propagation が単体テストで固定される, so that 後続 UI 実装が API 契約違反を持ち込まない

#### Acceptance Criteria

1. When detail fetch is tested with a mock transport, the test suite shall verify method `GET` and path `/api/items/{id}`.
2. When detail fetch succeeds, the test suite shall verify returned `ItemDetail` includes `content` and preserves RFC3339 strings without `Date` conversion.
3. When detail fetch is authenticated, the test suite shall verify the request carries a Bearer token through the existing APIClient path.
4. When read-only state update is tested, the test suite shall verify method `PUT`, path `/api/items/{id}/state`, and body containing `is_read` only.
5. When star-only state update is tested, the test suite shall verify method `PUT`, path `/api/items/{id}/state`, and body containing `is_starred` only.
6. When combined read and star state update is tested, the test suite shall verify both fields are present with the requested Boolean values.
7. When state update receives a successful 2xx response with an empty or ignored body, the test suite shall verify the repository treats it as success.
8. When detail fetch or state update receives a Feedman error response, the test suite shall verify typed error context is preserved.
9. When detail fetch or state update receives an authenticated `401` followed by refresh retry in APIClient tests, this repository test suite may rely on #23 coverage and shall not duplicate refresh token rotation logic.
10. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Architecture and compatibility

1. The implementation shall support iOS 16+ and Swift Concurrency.
2. The repository shall follow MVVM + Repository の既存方針に従い、View が直接 `URLSession`、Keychain、または request body encoding を扱わないようにする。
3. The repository shall reuse existing API layer types such as `APIClient`, `ItemDetail`, `ItemStateUpdateRequest`, and `FeedmanAPIError` instead of redefining endpoint-local JSON models where avoidable.
4. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Security

1. The implementation shall not commit real access tokens, refresh tokens, OAuth codes, Secret、または個人情報。
2. Repository tests shall use representative dummy tokens and dummy item ids only.
3. The repository shall not read refresh token from Keychain directly; refresh token lifecycle remains `AuthRepository` / `TokenStore` and APIClient refresh hook の責務とする。

### NFR 3: Scope control

1. The implementation shall keep changes within `Feedman/` and `FeedmanTests/` unless Xcode project wiring requires adjacent project-file updates.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not create PRs, invoke reviewer / project-manager agents, or perform commits as part of this Stage A requirements task.
4. The implementation shall not introduce Detail UI, Safari presentation, optimistic cross-screen sync, or list pagination behavior.

## 実装境界

- `ItemRepository` の method signatures は既存 app environment の access token 保持方式に合わせて決める。現状の `AppAuthenticationState.authenticated(accessToken:)` と APIClient の `accessToken` parameter を自然に接続できる形を優先する。
- State update method は API 契約上 partial body を送ることを固定し、成功時に updated item body が返ることは前提にしない。
- 401 refresh retry、refresh hook の直列化、refresh token rotation、credential clear は #23 / #20 の責務であり、本 Repository は endpoint request と typed error propagation に集中する。
- Mock repository は UI preview data としても使えるが、prototype の mock JSON 形を API 契約として扱わない。

## テスト観点

- `GET /api/items/{id}` の method / path / Bearer header。
- `ItemDetail` decode と `content` / RFC3339 string / nullable favicon の保持。
- `PUT /api/items/{id}/state` の method / path / Bearer header。
- read-only body が `{"is_read":true}` または requested Boolean のみになること。
- star-only body が `{"is_starred":true}` または requested Boolean のみになること。
- combined body が `is_read` と `is_starred` の両方を含むこと。
- state update success が response body に依存しないこと。
- Feedman standard error が typed context として caller に届くこと。
- Mock repository が requested partial state values を記録し、失敗設定時に configured error を返すこと。
- Xcode が利用可能な macOS 環境では `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行すること。

## 確認事項

- `PUT /api/items/{id}/state` の成功 response body は `design/SPEC-iOS.md` / `design/SERVER.md` に明記されていないため、client は 2xx を成功として扱い、updated item body を必須にしない前提でよいか。
- `ItemRepository` method が access token を引数で受け取るか、environment / session abstraction から取得するかは、実装時点の AppEnvironment と後続 feature wiring に合わせて確定する必要がある。
- state update method を read / star の個別 method と combined partial method のどちらで公開するかは、partial body 契約を破らない範囲で既存 code style に合わせて決める必要がある。
