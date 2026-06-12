# Issue #38 Subscriptions repository and real drawer data 要件定義

## 概要

Issue #38 は Parent: #8 の子 Issue として、authenticated app shell の drawer feed list を mock data から real subscriptions API へ差し替える。
`design/SPEC-iOS.md` では v1 の採用ナビゲーションを左ドロワー + 記事ビューに固定し、ドロワー内に「すべての新着」「お気に入り」、フィード一覧、アカウント導線を表示すると定義している。
`GET /api/subscriptions` は Bearer token 認証必須の購読一覧 API であり、#23 の APIClient 401 refresh retry hook により access token 期限切れ時は refresh 後に 1 回 retry される前提で利用する。

Issue コメントでは、依存 `Depends on: #23, #28` が develop へ merge 済みであり、`codex-blocked` が除去され `codex-auto-dev` が付与されたことが人間により確認されている。Path Overlap Checker の edit paths は `Feedman/Core/`、`Feedman/Features/AppShell/`、`Feedman/Features/Subscriptions/` である。

#29 では `FeedRepository.subscriptions()` から drawer feed entries を読み込む repository-shaped mock data の契約が確定済みである。本 Issue ではその契約を保ったまま、`APIClientFeedRepository.subscriptions()` または同等の real repository 実装が `/api/subscriptions` から取得した API response を drawer 用 domain model へ map することを固定する。

## スコープ

- `Feedman/Core` にある subscriptions repository の real API integration を実装可能な要件として定義する。
- `FeedRepository.subscriptions()` が `GET /api/subscriptions` を認証付きで呼び、`Subscription` API model を drawer 表示用の `Feed` domain model へ変換する。
- authenticated shell 表示時に real repository から subscriptions を読み込み、drawer の feed section を repository state で更新する。
- subscriptions の loading / success / empty / error / retry state を drawer feed section で扱い、global route entries の操作を妨げない。
- unread count と feed status は API response を source of truth として drawer に反映する。
- access token の取得、401 refresh retry、typed error mapping は #23 までの APIClient / AuthRepository 境界を利用し、View が直接 `URLSession` や Keychain を触らない。

## スコープ外

- 購読設定 sheet、購読解除、fetch interval 変更、再開、手動 fetch などの subscription actions。
- フィード別記事一覧の本実装、filter、pagination、feed route content の API 接続。
- 横断タイムライン、スター一覧、検索、記事詳細、既読 / スター操作、SFSafariViewController の追加実装。
- フィード登録 UI または `POST /api/feeds` の実装変更。
- キーワードプッシュ通知 UI と drawer 導線。
- API 契約、`design/SPEC-iOS.md`、`design/SERVER.md`、確定済み `docs/specs/*` の変更。
- prototype mock data の JSON 形、`favicon_letter`、`favicon_color` など視覚専用 field の導入。

## 受入基準

### Requirement 1: Real subscriptions repository

**Objective:** As a Feedman user, I want drawer feeds to come from my real subscriptions, so that the drawer reflects the account I am signed in with

1. When `FeedRepository.subscriptions()` is called on the real repository, it shall send an authenticated `GET /api/subscriptions` request.
2. When `/api/subscriptions` returns subscriptions, the repository shall map each API `Subscription` to the drawer domain model without using `AppShellPreviewData.drawerFeeds` or prototype mock JSON as the source of truth.
3. When a subscription has a stable `feed_id`, the drawer feed route shall use that feed identifier for `AppShellRoute.feed(id:title:)`.
4. When a subscription has a display title, the drawer shall use the API `feed_title` as the feed row title.
5. If the API response contains duplicate feed identifiers, the app shall avoid crashing and shall keep route selection deterministic for rendered rows.

### Requirement 2: Authenticated shell loading

**Objective:** As an authenticated user, I want subscriptions to load when the app shell appears, so that navigation is populated without requiring a manual drawer action

1. When authenticated shell appears, subscriptions shall load from the repository.
2. When the authenticated shell reappears after login completion, the drawer shall not keep stale unauthenticated or preview-only feed data as the primary feed list.
3. When subscriptions are already loaded and a reload starts, the drawer shall keep the existing feed rows visible or show a lightweight loading state without blocking global navigation.
4. When the user remains authenticated across route changes, route selection shall not trigger unnecessary duplicate subscription loads unless the implementation explicitly performs a refresh.
5. If authentication is lost or refresh fails with an auth-required error, the subscriptions load shall surface a recoverable shell state or allow the app-level auth flow to handle reauthentication without crashing.

### Requirement 3: Error and retry state

**Objective:** As a Feedman user, I want drawer loading failures to be visible and recoverable, so that I can retry instead of seeing an empty feed list

1. When subscriptions fail, drawer/feed area shall expose retry/error state.
2. When subscription loading fails, the drawer feed section shall not misrepresent the failure as an empty subscription list.
3. When subscription loading fails after previously loaded feeds exist, the drawer may keep those feeds visible, but it shall also expose that the latest load failed.
4. When the retry control is activated, the app shall call the repository load path again.
5. When retry succeeds, the drawer shall replace the error state with the latest loaded subscriptions.
6. When retry fails again, the drawer shall keep a non-crashing error state and continue to allow `すべての新着`、`お気に入り`、`アカウント` navigation.

### Requirement 4: Unread count and status reflection

**Objective:** As a Feedman user, I want unread counts and feed status in the drawer to match server state, so that I can choose a feed based on current repository data

1. When unread counts update, drawer shall reflect the repository state.
2. When a subscription's `unread_count` is greater than zero, the drawer shall show a corresponding unread badge.
3. When a subscription's `unread_count` is zero, the drawer shall not show a positive unread badge.
4. When a subscription's `feed_status` is `active`, the drawer shall not show stopped or error warning text for that row.
5. When a subscription's `feed_status` is `stopped`, the drawer shall show a stopped indicator or short Japanese label such as `停止中`.
6. When a subscription's `feed_status` is `error`, the drawer shall show an error indicator or short Japanese label such as `取得エラー`.
7. If `error_message` is present for a stopped or error subscription, the repository shall preserve it in domain state where practical, but this Issue shall not require a settings or recovery action for the feed itself.

### Requirement 5: APIClient and auth refresh integration

**Objective:** As a Repository 実装者, I want subscriptions API calls to use the shared authenticated transport, so that endpoint code does not duplicate token refresh behavior

1. When `/api/subscriptions` initially returns `401` for an authenticated request, the APIClient shall apply the #23 refresh retry behavior before surfacing failure to the repository caller.
2. When refresh and retry succeed, the repository shall return the retried `/api/subscriptions` result to the drawer state as a normal success.
3. When refresh fails, the repository or AppShell state shall surface an auth-required or recoverable error without reading or clearing Keychain directly in the View.
4. When `/api/subscriptions` returns non-auth endpoint errors, the repository shall preserve enough typed error context for the drawer error message and tests.
5. The subscriptions repository shall not call `/api/auth/refresh` directly unless that call is already owned by the #23 APIClient / AuthRepository refresh hook boundary.

### Requirement 6: Drawer navigation compatibility

**Objective:** As a Feedman user, I want real drawer data to preserve the route behavior introduced by #28 and #29, so that adding API data does not regress shell navigation

1. When the drawer renders real subscription data, it shall still include `すべての新着`、`お気に入り`、`アカウント` and in-scope footer actions already present in the shell.
2. When the user selects a feed row loaded from the real repository, the drawer shall close and route state shall update to that feed's item-list route.
3. If a selected feed is absent from a later subscription reload, the shell shall keep the safe fallback behavior defined by #28 and shall not crash.
4. When real subscription data is loading, empty, or failed, global drawer route selection shall remain usable.
5. When the drawer renders v1 navigation, it shall not expose keyword notification settings or keyword notification drawer entries.

### Requirement 7: Favicon / avatar data handling

**Objective:** As a Feedman user, I want feed rows to keep the established favicon behavior, so that real API data does not break drawer visuals

1. When a subscription contains `favicon_url` as a valid `data:` URL, the drawer shall render it through the dedicated favicon component rather than `AsyncImage(url:)`.
2. When `favicon_url` is `null`, missing, invalid, or unsupported, the drawer shall render a deterministic title-derived fallback avatar.
3. When switching from mock to real repository data, the drawer row dimensions shall remain stable across favicon and fallback states.
4. If the current drawer domain model does not yet carry favicon source, this Issue may add the minimum domain field needed to preserve the API value, but it shall not introduce prototype-only favicon fields.

## API / データ契約

- Endpoint: `GET /api/subscriptions`
- 認証: `Authorization: Bearer <access_token>`。`401` は #23 の APIClient refresh retry hook に従う。
- Response: subscriptions の配列として扱う。既存 `Subscription` API model と fixture に合わせ、少なくとも以下の field を扱う。
  - `id: String`: subscription identifier。設定 / 解除など将来の subscription actions 用に保持できる。
  - `feed_id: String`: feed-specific route の stable identifier。
  - `feed_title: String`: drawer 表示名。
  - `feed_url: String?`
  - `site_url: String?`
  - `favicon_url: String?`: `data:<mime>;base64,...` または `null`。
  - `fetch_interval_minutes: Int`
  - `feed_status: "active" | "stopped" | "error"`
  - `error_message: String?`
  - `unread_count: Int`
- Domain mapping:
  - `feed_id` を `Feed.id` または route 用 stable feed identifier へ map する。
  - `feed_title` を `Feed.title` へ map する。
  - `unread_count` を `Feed.unreadCount` へ map する。負数が返った場合の扱いは server contract 外の異常として、実装時に 0 clamp または decode/domain error のいずれかへ明示する。
  - `feed_status=active` は `.active`、`stopped` は `.stopped(message:)`、`error` は `.error(message:)` へ map する。message は `error_message` が無い場合も UI が短い既定 label を表示できるようにする。
  - `favicon_url` は drawer row が参照できる domain field または view state へ保持する。`data:` URL は画像表示専用 component へ渡し、`AsyncImage` に直接渡さない。
- Pagination: `GET /api/subscriptions` には本 Issue では cursor pagination を要求しない。pagination helper は横断タイムライン等の別 endpoint の責務とする。
- Error: サーバーエラー body は `{ error: { code, message, category, action, details? } }` の既存形式を利用する。UI 表示文は user-facing な短い日本語へ変換し、debug 用詳細や token 値を表示しない。

## UI / 状態要件

- Drawer feed section は `loading`、`loaded`、`empty`、`failed` を表現できる。retry を追加する場合は `failed` state から起動できること。
- Loading state は drawer 全体を塞がず、global route entries と footer actions を操作可能に保つ。
- Empty state は「購読フィードがありません」等、失敗ではないことが分かる短い日本語表示にする。
- Failed state は「フィードを読み込めませんでした」等の短い日本語表示と retry affordance を持つ。retry affordance はボタンまたは同等の明示操作にする。
- Feed row は #29 の layout 契約を維持し、左に favicon / avatar、中央に feed title と必要に応じた status、右に unread count badge を配置する。
- Feed title、status、unread badge は Dynamic Type や長い feed title で重ならないようにする。
- Accessibility label / value は feed title、選択状態、未読数、停止 / エラー状態を日本語で伝える。
- Real repository data に切り替えても、selected drawer item、toolbar title、drawer open / close の state source of truth は #28 の route state に従う。

## テスト要件

- Repository unit test:
  - When `/api/subscriptions` returns a representative JSON array, the real repository shall call `GET /api/subscriptions` with bearer auth and preserve feed id、title、unread count、status、favicon source in the mapped drawer state.
  - When `/api/subscriptions` returns an empty array, the repository shall return an empty list and AppShell state shall represent empty feed section.
  - When `/api/subscriptions` returns `feed_status` values `active`、`stopped`、`error`, mapping shall preserve the corresponding drawer status.
  - When `/api/subscriptions` fails with non-auth API error, the drawer ViewModel shall surface failed state rather than empty state.
  - When initial `401` is followed by successful refresh retry, tests shall verify the subscriptions call succeeds through the shared APIClient behavior or a repository-level integration test using mock transport.
  - Unit tests shall not depend on real network, real OAuth, real Keychain, real server, real tokens, or personal data.
- AppShell / ViewModel unit test:
  - When authenticated shell triggers subscription loading, the drawer feed ViewModel shall move through loading to loaded / empty / failed state.
  - When retry is invoked from failed state, the ViewModel shall call the repository again and update state from the new result.
  - When a loaded feed is selected, the stable feed identifier and title shall be passed to `AppShellRoute.feed(id:title:)`.
  - When loading fails after existing feeds are present, tests shall verify whether existing feeds are retained and that the latest failure is visible.
- Decode / fixture test:
  - Existing `Subscription` decode fixture shall remain valid for `favicon_url`、`feed_status`、`error_message`、`unread_count`。
  - If a subscriptions array fixture is added, it shall contain no secrets, real tokens, or personal information.
- macOS/Xcode 環境では以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 実装境界

- Core:
  - `FeedRepository` protocol の既存 `subscriptions()` contract を維持する。
  - Real repository は `APIClient` と access token provider / auth boundary を利用し、View や ViewModel へ transport detail を漏らさない。
  - `Subscription` API model の response shape が既存 fixture と異なる場合は、実装を広げず仕様差分として PM / Architect へ確認する。
- AppShell:
  - `AppShellDrawerFeedViewModel` または同等の小さな shell state object が loading / success / empty / failure / retry を調停する。
  - `RootView` は authenticated shell 表示時に repository load を開始してよいが、直接 `URLSession`、Keychain、raw endpoint URL を扱わない。
  - Drawer の route selection と selected state は #28 / #29 の契約を維持する。
- Subscriptions feature:
  - 本 Issue で `Feedman/Features/Subscriptions/` を使う場合は repository / state の補助に限定し、settings sheet や subscription actions を実装しない。
- Scope control:
  - 実装 PR ではこの要件定義を根拠に `design/SPEC-iOS.md`、`design/SERVER.md`、他 Issue の確定 specs を変更しない。
  - 実装コミット、PR 作成、reviewer / project-manager 起動は本 PM 作業の範囲外。

## 確認事項

- 現時点で Issue #38 を実装前に追加確認すべき blocker はない。
- `GET /api/subscriptions` の top-level response は、既存 `Subscription` fixture と API model に合わせて subscriptions 配列として扱う。サーバーが wrapper object を返す場合は実装前に仕様差分として確認する。
- `Subscription.id` と `feed_id` の使い分けは、drawer route には `feed_id`、将来の settings / unsubscribe actions には `id` を使う方針とする。
- Unread count の即時更新源は本 Issue では subscriptions reload の repository state とする。記事既読化やスター操作後に drawer count を楽観更新する横断同期は、該当 feature Issue の責務とする。
- Retry UI の具体的な見た目は既存 DesignSystem / AppShell の部品に合わせて実装時に決めてよい。ただし error を空状態として隠さないことは固定する。
