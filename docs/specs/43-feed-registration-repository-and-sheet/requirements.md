# Issue #43 Feed registration repository and sheet 要件定義

## 背景

Issue #43 は Parent: #9 の子 Issue として、フィード登録 sheet から URL を送信し、`POST /api/feeds` によるフィード自動検出・登録結果をユーザーへ表示する。
`design/SPEC-iOS.md` では v1 スコープにフィード登録が含まれ、登録 UI は `.sheet` で表示し、URL 入力 → 検出 → 確認 → 登録、専用レート制限と重複登録エラーを扱うと定義されている。
API 契約は `design/SPEC-iOS.md` と `design/SERVER.md` を優先し、prototype の `design/mobile/fm-sheets.jsx` は見た目、状態遷移、文言の参考に留める。mock data の JSON 形は API 契約として扱わない。

Issue コメントでは、依存 #23 / #27 は GitHub Issue state が `OPEN` のままでも `develop` へ merge 済みであり、`codex-blocked` が除去され `codex-auto-dev` が付与されたことが人間により確認されている。本要件ではこの決定を前提として扱い、追加ブロックとはしない。
Path Overlap Checker の edit path は `Feedman/Core/`、`Feedman/Features/`、`FeedmanTests/`、`Feedman.xcodeproj/` である。

## 現行コンテキスト

- `Feedman/Core/APIModels.swift` には `FeedRegistrationRequest` と `FeedRegistrationResponse` が存在し、`FeedmanTests/Fixtures/feed_registration_response.json` では登録成功レスポンスが購読相当の flat response として decode 済みである。
- `Feedman/Core/FeedRepository.swift` には `FeedRepository.subscriptions()` と cross-feed 系の契約があるが、登録メソッドと `APIClientFeedRepository` の `POST /api/feeds` 実装は未実装である。
- `Feedman/Features/AppShell/RootView.swift` には drawer footer の「フィードを登録」導線と `AppShellPresentation.feedRegistration` があり、現状は placeholder sheet でネットワーク送信しない。
- Issue #27 の共有 primitive として `FeedmanSheetShell`、loading、error、toast/banner が存在するため、登録 sheet は可能な範囲でそれらを利用する。
- Issue #23 により、認証付き API の `401` refresh retry hook は利用可能な前提とする。

## スコープ

- `FeedRepository` にフィード登録の repository protocol を追加し、real / mock implementation を差し替え可能にする。
- Real repository は認証付き `POST /api/feeds` を `FeedRegistrationRequest { url }` で呼び、`FeedRegistrationResponse` を decode する。
- 登録成功レスポンスを drawer や後続 subscription UI が扱える domain model へ変換する。
- `Feedman/Features/RegisterFeed` または既存 AppShell 配下の適切な feature 境界に、登録 sheet、ViewModel、UI state を追加する。
- AppShell の「フィードを登録」導線から placeholder ではなく登録 sheet を表示する。
- 登録の loading / success / empty input / error 表示を実装し、重複、rate-limit、invalid URL の guidance を出し分ける。
- 登録成功後にユーザーが sheet を閉じられ、必要に応じて drawer の feed list を再読み込みまたは登録結果を反映できる境界を用意する。
- Unit test は repository、ViewModel state、error mapping を中心に、実ネットワークや実 Keychain に依存せず検証する。

## スコープ外

- OPML import / export。
- manual feed metadata editing。
- フィード URL 変更 UI。
- キーワード通知 UI、drawer 導線、push device / keyword API。
- 購読設定 sheet の本実装、購読解除、再開、フェッチ間隔変更、手動 fetch。
- フィード別記事一覧、横断タイムライン、スター一覧、検索、記事詳細 sheet の本実装。
- サーバー API 契約の変更、エンドポイント追加、prototype mock JSON shape の採用。
- 既存 `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更。

## 要件

### Requirement 1: Feed registration repository contract

**Objective:** As a Feature ViewModel 実装者, I want フィード登録を repository protocol 経由で呼べる, so that View が `URLSession` や APIClient details に直接依存しない

#### Acceptance Criteria

1. When the feature needs to register a feed URL, the app shall expose a `FeedRepository` method or narrowly scoped repository protocol method for feed registration.
2. When registration is requested, the repository shall accept the user-entered URL as a `String` and build `FeedRegistrationRequest` with `url` without adding prototype-only fields.
3. When the real repository sends the request, it shall call `POST /api/feeds` with JSON body and Bearer authentication.
4. When the server returns success, the repository shall decode `FeedRegistrationResponse` using the canonical API model shape.
5. When `FeedRegistrationResponse` contains `favicon_url`, the model shall keep it as `String?`; the implementation shall not decode `data:` URL through `AsyncImage`.
6. When mapping registration success for drawer display, the implementation shall preserve stable subscription/feed identifiers separately from display title.
7. When the existing `FeedRepository` shape becomes too broad, the implementation may introduce a small registration-specific protocol, but AppShell/RegisterFeed shall still depend on a mockable abstraction.

### Requirement 2: Real API behavior and auth boundary

**Objective:** As an authenticated Feedman user, I want the registration operation to use the same authenticated API path as other v1 repositories, so that expired access tokens and API errors behave consistently

#### Acceptance Criteria

1. When the user submits a valid URL, the repository shall call `/api/feeds` exactly once for that submit action unless APIClient performs the #23 one-time `401` refresh retry internally.
2. When an access token is expired and refresh succeeds, the registration operation shall be retried through the APIClient refresh hook without the sheet implementing token refresh logic.
3. When refresh fails or credentials are unavailable, the ViewModel shall surface an auth-required state or error that the app can route to login/logout handling in a later integration.
4. When the server returns `400` / validation error, the repository shall preserve the `FeedmanAPIError.feedmanError` context for ViewModel mapping.
5. When the server returns `429`, the repository shall preserve `details.retry_after_seconds` and `Retry-After`-derived metadata already exposed by the API error layer where available.
6. When transport or malformed response failure occurs, the repository shall not convert it into success, duplicate, or validation guidance.
7. The sheet and ViewModel shall not read or write Keychain directly.

### Requirement 3: Register feed ViewModel state machine

**Objective:** As a user, I want URL submission to have clear loading, success, and failure states, so that I can understand whether the feed was registered

#### Acceptance Criteria

1. When the sheet first opens, the ViewModel shall start in an input state with an empty URL or the caller-provided initial URL.
2. When the URL text is empty or only whitespace, submit shall not call the repository and shall show inline guidance or keep the primary action disabled.
3. When the URL text has leading or trailing whitespace, submit shall trim it before building the request.
4. When submit begins, the ViewModel shall enter a loading state and prevent duplicate concurrent submit calls for the same visible sheet.
5. While loading, the primary action shall communicate progress and remain stable in size.
6. When registration succeeds, the ViewModel shall expose the registered feed title and identifiers from `FeedRegistrationResponse`.
7. When registration succeeds, the ViewModel shall allow the sheet to dismiss and shall emit a success event that AppShell can use to refresh drawer feeds or show a toast.
8. When registration fails, the ViewModel shall keep the entered URL editable unless the failure is auth-required and app-level auth handling takes over.
9. When the sheet is dismissed and reopened for a new registration, stale success or error state shall not leak into the new session.

### Requirement 4: Specific error guidance

**Objective:** As a user, I want duplicate, invalid URL, and rate-limit errors to be explained specifically, so that I know whether to edit the URL, wait, or stop

#### Acceptance Criteria

1. When the API error code/category indicates an invalid URL or validation failure, the sheet shall show guidance that the user should check the site URL or RSS/Atom URL.
2. When the API error code/category indicates a duplicate subscription/feed, the sheet shall show guidance that the feed is already registered and shall not imply a server outage.
3. When the API error code is `FEED_COOLDOWN` or category is `rate_limit`, the sheet shall show retry-later guidance and include `retry_after_seconds` when available.
4. When a non-specific server error occurs, the sheet shall show a recoverable generic error and allow retry.
5. When a transport error occurs, the sheet shall distinguish network failure from URL validation where practical.
6. When the API error body contains a user-safe `message`, the ViewModel may use it as supporting text, but shall not expose raw debug details, token values, or personally sensitive data.
7. Error mapping shall be implemented in ViewModel/domain presentation code, not inside shared DesignSystem primitives.

### Requirement 5: Sheet UI and AppShell integration

**Objective:** As a Feedman user, I want to open feed registration from the drawer and complete it in a bottom sheet, so that adding a subscription stays within the main app flow

#### Acceptance Criteria

1. When the user taps drawer footer「フィードを登録」, the app shall present the registration sheet instead of the current placeholder content.
2. When the registration sheet is presented, it shall use SwiftUI `.sheet` with iOS 16+ compatible detents; `.medium` is acceptable for the initial form.
3. The sheet shall include title「フィードを登録」, short guidance「サイトの URL か RSS/Atom の URL を入力してください」相当, URL input, dismiss control, and primary submit action.
4. The URL input shall use URL-appropriate keyboard/content type where SwiftUI supports it.
5. The primary action shall be disabled or guarded while input is invalid or submit is already running.
6. When registration succeeds, the sheet shall show the detected/registered feed title and a clear completion affordance.
7. When the user completes or dismisses after success, AppShell shall dismiss the sheet and show a success toast/banner or otherwise visible success feedback.
8. When registration succeeds, drawer feed list shall be refreshed or updated so the newly registered feed can appear without requiring app relaunch.
9. The sheet shall use `FeedmanTheme` and #27 shared primitives where appropriate, and shall avoid hard-coded feature-local colors when semantic tokens exist.
10. The sheet shall not show keyword notification controls, OPML controls, manual metadata editing, or feed URL change controls.

### Requirement 6: Mock repository and preview behavior

**Objective:** As a Developer, I want feed registration to be testable and previewable without the real server, so that UI and state handling can be verified independently

#### Acceptance Criteria

1. When using `MockFeedRepository` or a test stub, registration shall be able to return a deterministic successful `FeedRegistrationResponse` or equivalent domain result.
2. When mock registration succeeds, subsequent mock `subscriptions()` calls should be able to include the registered feed or the ViewModel/AppShell shall expose another deterministic success path for drawer refresh tests.
3. When mock registration is configured to fail, the ViewModel shall exercise the same error states as real repository failures.
4. Mock data shall not introduce prototype-only fields such as `favicon_letter` or `favicon_color`.
5. SwiftUI previews, if added, shall cover input, loading, success, and representative error states without using real network or real tokens.
6. Preview/test URLs shall be generic examples and shall not contain secrets or personal information.

### Requirement 7: Accessibility and layout resilience

**Objective:** As a mobile user, I want the registration sheet to remain usable with Dynamic Type and VoiceOver, so that registration is accessible

#### Acceptance Criteria

1. When VoiceOver is enabled, the dismiss control, URL field, submit action, loading state, error message, and success result shall have meaningful accessible labels.
2. When Dynamic Type is larger, title, guidance, field, error text, and buttons shall wrap or resize without overlapping.
3. When a long URL is entered, the text field shall not push primary controls outside the visible sheet chrome.
4. When error guidance is long, critical retry timing or duplicate/invalid explanation shall remain readable.
5. The submit and dismiss controls shall keep iOS-appropriate touch targets.
6. The sheet shall not rely on color alone to distinguish success, loading, and error states.

### Requirement 8: Test coverage and verification

**Objective:** As a QA/Developer, I want focused tests for registration repository and ViewModel behavior, so that later app integration can rely on this feature boundary

#### Acceptance Criteria

1. When unit tests are added for the real repository, they shall use mock `APITransport` and verify `POST /api/feeds`, JSON body `{"url": ...}`, and Bearer authorization.
2. When the real repository receives the success fixture shape, tests shall verify that `FeedRegistrationResponse` values are preserved and mapped to the expected domain result.
3. When the repository receives duplicate, invalid URL, and rate-limit API errors, tests shall verify that typed error context remains available to the ViewModel.
4. When ViewModel submit receives an empty or whitespace-only URL, tests shall verify that repository is not called.
5. When ViewModel submit succeeds, tests shall verify loading → success transition, success event emission, and registered feed display data.
6. When ViewModel submit fails, tests shall verify loading → error transition and that URL input remains available for correction or retry.
7. When duplicate submit is attempted while loading, tests shall verify that only one repository call is made.
8. When drawer/AppShell integration is tested, tests shall verify that selecting「フィードを登録」presents registration and that success can trigger feed list refresh/update.
9. Unit tests shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
10. When macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and Swift Concurrency (`async` / `await`).
3. Views shall not directly touch `URLSession`, Keychain, or raw token storage.
4. Swift type names, identifiers, and file names shall be English.
5. API date string handling shall remain unchanged; this Issue shall not introduce automatic `Date` decoding.

### NFR 2: API contract control

1. The implementation shall follow `design/SPEC-iOS.md` and `design/SERVER.md` before prototype files.
2. The implementation shall not require server API fields beyond `FeedRegistrationRequest` / `FeedRegistrationResponse` and the canonical error response shape already present in Core.
3. The implementation shall not change `/api/feeds` semantics from URL automatic detection and registration.
4. The implementation shall keep `favicon_url` as `String?` and use the dedicated favicon path if any UI renders it later.

### NFR 3: Scope control

1. The implementation shall remain within Issue #43 の feed registration repository and sheet responsibility.
2. The implementation shall not implement OPML, manual metadata editing, feed URL change UI, subscription settings actions, or keyword notification.
3. The implementation shall not rewrite finalized specs for other Issues.
4. The implementation shall not create PRs, invoke Reviewer/PjM agents, or perform release operations as part of Stage A/implementation of this spec.

## 実装境界

- Core 側は `FeedRepository` / `APIClientFeedRepository` / `MockFeedRepository` / API model mapping に閉じ、UI 文言や sheet presentation state を持たない。
- Feature 側は登録 sheet と ViewModel state machine を持ち、API error を user-facing guidance に変換する。
- AppShell は drawer 導線、sheet presentation、成功後の dismiss/toast/feed list refresh だけを担当し、URL validation や repository request construction を持たない。
- 登録成功後に新規 feed route へ自動遷移するかどうかは必須にしない。v1 としては成功表示、dismiss、drawer feed list 反映を固定する。
- `POST /api/feeds` は「URL 入力 → 検出 → 登録」を 1 API 操作として扱う。prototype の二段階風 UI は視覚参考であり、別の検出 API を要求しない。

## 確認事項

- #23 / #27 は Issue state が `OPEN` でも、#43 コメントの人間判断により `develop` merge 済みとして扱う。
- `FeedRegistrationResponse` の既存 fixture は flat subscription-like response であり、現時点の iOS Core API model として扱える。
- Duplicate / invalid URL の具体的な server error `code` 名は `design/SPEC-iOS.md` に列挙されていないため、実装では `code` と `category` の両方を見て保守的に guidance を出し、未識別 code は generic recoverable error に落とす。
- 成功後に drawer feed list を「再取得」するか「登録結果をローカルに挿入」するかは実装時に既存 `AppShellDrawerFeedViewModel` との整合で選んでよい。ただしアプリ再起動なしに反映できることを要求する。
- `design/mobile/fm-sheets.jsx` の `FMRegisterSheet` は見た目と状態遷移の参考にするが、mock timer や prototype-only state は実装契約にしない。
