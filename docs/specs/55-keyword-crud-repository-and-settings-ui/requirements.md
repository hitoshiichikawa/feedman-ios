# Issue #55 Keyword CRUD repository and settings UI 要件定義

## 背景

Issue #55 は Parent: #13 の子 Issue として、キーワードプッシュ通知の次フェーズにおける iOS 側の keyword 管理 UI と `/api/keywords` repository を定義する。Issue #54 で APNs device registration foundation が `codex-staged-for-release` まで進んでいるため、本 Issue では通知基盤を前提に、ユーザーが通知対象キーワードを一覧・追加・編集・有効化/無効化・削除できる薄い縦切りを扱う。

`design/SERVER.md` §2.3 では `/api/keywords` として `GET /api/keywords`、`POST /api/keywords`、`PATCH /api/keywords/{id}`、`DELETE /api/keywords/{id}` が定義され、keyword は `{ id, term, scope, enabled, hits }` を返す。`scope` は `title` として追加され、`hits` は過去 N 日の一致数を UI 表示用に返す。`design/SPEC-iOS.md` §7 / §5.8 ではキーワードプッシュは v1 ではなく次フェーズ対象であり、本 Issue はその次フェーズ子 Issue として扱う。

Issue コメントでは人間の追加決定事項はなく、Path Overlap Checker の edit paths は `Feedman/Core/`、`Feedman/Features/Notifications/`、`FeedmanTests/` である。依存 Issue #54 は `codex-staged-for-release` ラベル付きで、手動復旧後の検証結果も記録されているため、本要件では実装ブロックとして扱わない。

## スコープ

- `Keyword` API model、request/response model、repository protocol、real/mock implementation を `Feedman/Core` に追加する。
- Real repository は Bearer 認証付きで `/api/keywords` の list/create/update/delete を呼ぶ。
- Keyword settings ViewModel を `Feedman/Features/Notifications` に追加し、初回 load、refresh、create、edit、enabled toggle、delete、duplicate/rate-limit error guidance を扱う。
- Keyword settings sheet を SwiftUI で追加し、既存 `FeedmanTheme`、`FeedmanSheetShell`、banner/loading/empty/error primitive を再利用する。
- AppShell から keyword settings sheet を開ける導線を追加する。ただし server-side matching worker、notification delivery、deep link routing は扱わない。
- Unit test は API request/decode、ViewModel state/error mapping、AppShell presentation 境界を中心に実ネットワークや実 APNs に依存せず検証する。

## スコープ外

- サーバー側 `/api/keywords` 実装、DB migration、matching worker、push job enqueue、FCM/APNs 配信。
- 通知タップ後の `feedman://items/{id}` deep link 完成実装。
- Body/content keyword matching、feed-scoped keyword、複数 scope 選択 UI。
- OPML import/export、feed URL 変更 UI、offline full-text cache。
- `/api/devices` foundation の再設計、APNs token canonicalization の変更、logout device unregister policy の変更。
- 既存 `docs/specs/*`、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更。

## API 契約

### `GET /api/keywords`

- 用途: 現在のログインユーザーの keyword 一覧を取得する。
- 認証: Bearer token 必須。
- Response item fields: `id`, `term`, `scope`, `enabled`, `hits`。
- iOS 側の扱い: `scope` は現スコープでは `title` のみを有効値として扱う。未知 scope は decode 失敗ではなく UI で編集対象外または generic 表示へ落とす実装判断を許容する。
- 未確認: 一覧 response が bare array か wrapper object かは仕様書に明記がない。実装時は既存 server 契約または実 API を確認し、フィールド意味を変えずに Codable 境界で吸収する。

### `POST /api/keywords`

- 用途: keyword を追加する。
- 認証: Bearer token 必須。
- Request body:

```json
{
  "term": "<keyword>",
  "scope": "title",
  "enabled": true
}
```

- Response: 追加後の keyword item を返す前提で設計する。サーバーが 201/200 か、body shape が異なる場合は実装前に確認する。

### `PATCH /api/keywords/{id}`

- 用途: keyword の `term` または `enabled` を更新する。
- 認証: Bearer token 必須。
- Request body: `term` と `enabled` の少なくとも片方を送る。`scope` は本 Issue では更新対象にしない。
- Response: 更新後の keyword item を返す前提で設計する。no-content 成功の場合は repository 境界で明示的に扱う必要があるため実装前に確認する。

### `DELETE /api/keywords/{id}`

- 用途: keyword を削除する。
- 認証: Bearer token 必須。
- Response: no-content 成功を扱える repository 境界を前提にする。

## 要件

### Requirement 1: Keyword API model contract

**Objective:** As a Developer, I want `/api/keywords` の API 型を Core に定義する, so that repository と UI が同じ canonical field を扱える

#### Acceptance Criteria

1. When keyword API models are introduced, the app shall define a keyword response model with `id`, `term`, `scope`, `enabled`, and `hits`.
2. When keyword create is requested, the app shall build a request body with `term`, `scope:"title"`, and `enabled`.
3. When keyword update is requested, the app shall build a patch request that includes only supported mutable fields: `term` and/or `enabled`.
4. When keyword data is decoded, the app shall keep server string fields as `String` and shall not introduce automatic `Date` decoding.
5. When unknown keyword `scope` values are received, the app shall not crash the settings UI.
6. When response shape ambiguity is encountered, the implementation shall resolve it at the Codable/repository boundary without changing the field semantics from `design/SERVER.md`.

### Requirement 2: Keyword repository CRUD behavior

**Objective:** As an authenticated Feedman user, I want keyword list operations to call `/api/keywords`, so that settings UI reflects server state

#### Acceptance Criteria

1. When keyword list opens, the repository shall call `GET /api/keywords` with Bearer authentication.
2. When keyword is added, the repository shall call `POST /api/keywords` with the create request body.
3. When keyword term is edited, the repository shall call `PATCH /api/keywords/{id}` with the edited `term`.
4. When keyword enabled state is toggled, the repository shall call `PATCH /api/keywords/{id}` with the edited `enabled` value.
5. When keyword is deleted, the repository shall call `DELETE /api/keywords/{id}`.
6. When an access token is expired and refresh succeeds, keyword operations shall rely on existing `APIClient` 401 refresh retry rather than implementing token refresh in Notifications.
7. When repository operations fail, typed `FeedmanAPIError` context shall remain available to the ViewModel.
8. The repository shall not touch `URLSession`, Keychain, or APNs APIs from SwiftUI views.

### Requirement 3: Keyword settings ViewModel state

**Objective:** As a user, I want keyword settings to show loading, success, empty, and error states, so that I understand current notification keyword state

#### Acceptance Criteria

1. When the settings sheet opens, the ViewModel shall load the keyword list.
2. When loading succeeds with keywords, the ViewModel shall expose a loaded list ordered according to repository response unless a later server contract defines sorting.
3. When loading succeeds with no keywords, the ViewModel shall expose an empty state with an affordance to add the first keyword.
4. When initial loading fails, the ViewModel shall expose a recoverable error and a retry action.
5. When refresh or mutation fails after a list is visible, the ViewModel shall preserve the visible list and show non-destructive guidance.
6. When duplicate concurrent load or mutation actions are attempted, the ViewModel shall prevent duplicate in-flight repository calls for the same visible operation.
7. When a new sheet session starts, stale success, edit, confirmation, or error state from a previous session shall not leak into it.

### Requirement 4: Keyword mutation validation and guidance

**Objective:** As a user, I want add/edit/toggle/delete feedback to be specific, so that I know whether to fix input, wait, or retry

#### Acceptance Criteria

1. When a keyword term is empty or whitespace-only, create/edit shall not call the repository and shall show inline guidance or keep the action disabled.
2. When a keyword term has leading or trailing whitespace, create/edit shall trim it before sending.
3. When the API error indicates duplicate keyword, the UI shall show guidance that the keyword is already registered.
4. When the API error indicates rate limit or returns status `429`, the UI shall show retry-later guidance and include `retry_after_seconds` when available.
5. When transport failure occurs, the UI shall distinguish network failure from validation or duplicate guidance where practical.
6. When auth-required occurs, the UI shall surface re-login guidance through the existing app-level auth-required pattern where available.
7. When delete is requested, the UI shall require an explicit confirmation before calling the repository.
8. When a toggle or delete mutation fails, the visible list shall not falsely show the failed server state as confirmed.

### Requirement 5: Keyword settings UI

**Objective:** As a Feedman user, I want a settings sheet for notification keywords, so that I can manage keyword notifications without leaving the main app flow

#### Acceptance Criteria

1. When the user opens keyword settings from AppShell, the app shall present a SwiftUI sheet instead of a placeholder.
2. When the sheet is presented, it shall use iOS 16+ compatible `.sheet` detents and the existing `FeedmanSheetShell` or equivalent shared shell.
3. The sheet shall show a title equivalent to「キーワード通知」and explain that matching is limited to article titles for this scope.
4. The sheet shall show each keyword term, enabled state, and `hits` count when available from the API model.
5. The sheet shall provide controls to add, edit, toggle enabled state, and delete keywords.
6. While an operation is in progress, the affected controls shall communicate progress and avoid layout shift.
7. The sheet shall use `FeedmanTheme` and shared primitives rather than hard-coded feature-local colors when semantic tokens exist.
8. The sheet shall not expose server worker controls, notification delivery diagnostics, feed-scoped search, OPML, or body/content matching controls.

### Requirement 6: AppShell integration and scope transition

**Objective:** As a user, I want a discoverable entry point to keyword settings, so that the next-phase feature can be used after v1 scope

#### Acceptance Criteria

1. When this next-phase feature is implemented, AppShell shall expose a keyword settings entry point in a drawer/footer location consistent with existing AppShell patterns.
2. When the keyword settings entry point is tapped, AppShell shall dismiss the drawer and present the keyword settings sheet.
3. When the sheet is dismissed, AppShell shall preserve the current route and visible timeline/feed/search state.
4. When keyword settings reports auth-required, AppShell shall show existing re-login guidance or route ownership feedback rather than silently failing.
5. The integration shall not change Timeline, Feed, Starred, Search, ArticleDetail, Account, or Subscription behavior except for the new keyword settings presentation.

### Requirement 7: Mocking and testability

**Objective:** As a Developer, I want keyword CRUD to be testable without real network or APNs, so that UI state and API contracts can be verified deterministically

#### Acceptance Criteria

1. When tests use a mock repository, it shall support deterministic list, create, update, toggle, delete, and failure scenarios.
2. When real repository tests run, they shall use mock `APITransport` and verify method, path, JSON body, and Bearer authorization for each CRUD operation.
3. When API model decode tests run, they shall verify `id`, `term`, `scope`, `enabled`, and `hits` preservation.
4. When ViewModel tests run, they shall verify loading, success, empty, initial error retry, mutation success, mutation failure preservation, duplicate action guard, and delete confirmation.
5. When duplicate/rate-limit error tests run, they shall verify user-facing guidance without exposing raw token values or private data.
6. Unit tests shall not depend on real network, real OAuth, real Keychain, real APNs, or personal data.

### Requirement 8: Accessibility, security, and project constraints

**Objective:** As a mobile user and maintainer, I want the keyword settings implementation to remain accessible, safe, and within the Issue boundary, so that the next-phase UI does not destabilize v1 features

#### Acceptance Criteria

1. When VoiceOver is enabled, keyword settings controls shall have meaningful labels for add, edit, enabled toggle, delete, loading, error, and retry states.
2. When Dynamic Type is larger, keyword terms, guidance, hits count, and action buttons shall wrap or resize without overlapping.
3. When a long keyword is entered, the input and list row shall not push primary controls outside the visible sheet chrome.
4. The implementation shall not log keyword terms together with tokens, Bearer tokens, refresh tokens, or personal account data.
5. The implementation shall keep `Feedman/Core` for API types/repository contracts and `Feedman/Features/Notifications` for UI/ViewModel coordination.
6. The implementation shall not rewrite finalized specs for other Issues.
7. Swift type names, identifiers, and file names shall be English.
8. When macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 受入基準（EARS）

- When keyword list opens, app shall fetch keywords.
- When keyword is added, app shall call `POST /api/keywords`.
- When keyword is edited, app shall call `PATCH /api/keywords/{id}`.
- When keyword is toggled, app shall call `PATCH /api/keywords/{id}` with `enabled`.
- When keyword is deleted, app shall call `DELETE /api/keywords/{id}` after explicit confirmation.
- When duplicate keyword errors occur, UI shall show duplicate guidance.
- When rate-limit errors occur, UI shall show retry-later guidance.
- When keyword operations fail after visible content exists, UI shall preserve visible content and show non-destructive feedback.
- When auth is required, UI shall surface re-login guidance through existing app-level patterns.
- The implementation shall not add server-side matching worker, notification delivery, or notification deep link routing in this Issue.

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and Swift Concurrency (`async` / `await`).
3. Views shall not directly touch `URLSession`, Keychain, APNs token storage, or raw auth token storage.
4. Swift type names, identifiers, and file names shall be English.

### NFR 2: API contract control

1. The implementation shall follow `design/SPEC-iOS.md` and `design/SERVER.md` before prototype files.
2. The implementation shall not require server API fields beyond `id`, `term`, `scope`, `enabled`, and `hits` for keyword display.
3. The implementation shall treat `scope:"title"` as the only create/update scope in this Issue.
4. The implementation shall preserve existing API error decoding and 401 refresh retry behavior.

### NFR 3: Scope control

1. The implementation shall remain within Issue #55 keyword CRUD repository and settings UI responsibility.
2. The implementation shall not implement server matching worker, push delivery, notification tap deep link, body/content matching, OPML, or feed-scoped search.
3. The implementation shall not rewrite finalized specs for other Issues.
4. The implementation shall keep #54 device registration behavior unchanged except for optionally displaying existing auth/permission guidance from AppShell or environment state.

## 実装境界

- Core 側は keyword API model、request model、repository protocol、real/mock repository に閉じ、UI 文言や sheet presentation state を持たない。
- Feature 側は keyword settings sheet と ViewModel state machine を持ち、API error を user-facing guidance に変換する。
- AppShell は drawer entry、sheet presentation、auth-required/toast boundary だけを担当し、keyword request construction や validation を持たない。
- Notifications feature は #54 の permission/device registration foundation を再設計しない。

## 確認事項

- `GET /api/keywords` の一覧 response shape が bare array か wrapper object かは仕様書に明記がない。実装前に既存 server 契約または実 API を確認する。
- `POST /api/keywords` / `PATCH /api/keywords/{id}` の成功 response が keyword item body を返すか、no-content 成功かは仕様書に明記がない。設計では item body を基本としつつ、実装前に確認する。
- Duplicate keyword の具体的な server error `code` 名は仕様書に固定列挙がない。実装では `code`、`category`、`statusCode` を組み合わせて保守的に guidance を出し、未識別 code は generic recoverable error に落とす。
- AppShell の keyword settings entry point は次フェーズ feature として追加する。過去 v1 spec の「keyword notification UI 非表示」は v1 制約であり、本 Issue の merge 後は #13 次フェーズ範囲として扱う。
