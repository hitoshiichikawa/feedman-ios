# Feedman iOS idd-codex Issue Backlog

作成日: 2026-06-08

このファイルは、`feedman-ios` のスケルトン作成後に idd-codex へ渡す GitHub Issue 草案です。
Issue 本文は `idd-codex-feature.yml` の入力項目に合わせています。

## 前提

- iOS クライアントは Swift + SwiftUI / iOS 16+ / MVVM + Repository で作る。
- v1 の認証は Cookie ではなく Bearer トークン方式を採用する。
- v1 ではキーワードプッシュ通知 UI は実装しない。ドロワー導線も非表示にする。
- 視覚基準は `design/Feedman iPhone.html` と `design/mobile/*.jsx`、API 契約は `design/SPEC-iOS.md` と `design/SERVER.md` を正とする。
- サーバー側のトークン認証実装が iOS 認証 Issue の前提条件になる。

## 推奨投入順

1. `feedman` 側: モバイル向けトークン認証 API
2. `feedman-ios` 側: Xcode/SwiftUI スケルトン
3. `feedman-ios` 側: ネットワーク・モデル・認証基盤
4. `feedman-ios` 側: デザインシステムと共通 UI
5. `feedman-ios` 側: タイムライン
6. `feedman-ios` 側: 記事詳細・既読・スター・Safari
7. `feedman-ios` 側: フィード一覧・購読設定
8. `feedman-ios` 側: フィード登録
9. `feedman-ios` 側: スター一覧・検索
10. `feedman-ios` 側: アカウント・ログアウト・退会
11. `feedman-ios` 側: 結合仕上げ・エラー/空/ローディング・アクセシビリティ
12. 次フェーズ: キーワードプッシュ通知

## GitHub Issue 分割結果（2026-06-08）

初期作成した GitHub Issue #2〜#13 は粒度が大きく、idd-codex / idd-claude の turn 上限内で実装完了できない可能性が高いため、Epic として扱う。Epic 自体には `codex-auto-dev` を付けない。

実装投入は以下の `task` ラベル付き子Issue単位で行う。子Issueにも現時点では `codex-auto-dev` を付けていない。依存が満たされたものから人間が個別に投入する。

| Epic | 子Issue |
|---|---|
| #2 API models/APIClient/pagination/error | #14 #15 #16 #17 #23 |
| #3 OAuth token login/auth storage | #18 #19 #20 #21 #22 |
| #4 Design system/shared UI | #24 #25 #26 #27 |
| #5 Drawer/app shell | #28 #29 #30 |
| #6 Cross-feed timeline | #31 #32 #33 |
| #7 Article detail/read/star/Safari | #34 #35 #36 #37 |
| #8 Feed list/subscription settings | #38 #39 #40 #41 #42 |
| #9 Feed registration | #43 #44 |
| #10 Starred/search | #45 #46 #47 |
| #11 Account/logout/delete | #48 #49 #50 |
| #12 v1 hardening | #51 #52 #53 |
| #13 Keyword push next phase | #54 #55 #56 |

粒度の基準:

- 1 Issue = 1 PR = 3〜6 acceptance criteria 程度。
- 変更ファイルの目安は 3〜8 個。
- API 型、APIClient、Repository、ViewModel、UI、polish を同一 Issue に詰め込まない。
- cross-feature state sync / auth refresh / Keychain / Safari / push deeplink は単独 Issue とする。

---

## Issue S1: モバイル向けトークン認証 API を追加する

対象 repo: `hitoshiichikawa/feedman`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: なし

背景・課題:

Feedman iOS はネイティブアプリのため、既存 Web の SameSite Cookie セッションを OAuth 後に安定して共有できない。iOS v1 のログインから API 呼び出しまでを成立させるには、既存 Cookie 認証を壊さずに Bearer トークン認証を追加する必要がある。

現状の挙動:

- Web は `/auth/google/login` から Google OAuth を行い、callback 後に `session_id` Cookie で認証する。
- 認証必須 API は Cookie セッション前提で、ネイティブ向けの token / refresh / revoke がない。

期待する挙動・ゴール:

- `flow=native` の OAuth callback がアプリスキーム `feedman://auth/callback?auth_code=...` へ一時コードを返す。
- iOS アプリは `POST /api/auth/token` で一時コードと PKCE verifier を交換し、access token / refresh token を取得できる。
- Bearer 付きの既存 API 呼び出しが Cookie 認証時と同じユーザー文脈で動く。
- 既存 Web の Cookie ログインと既存 API 動作は変わらない。

受入基準の候補:

- When `/auth/google/callback` が `flow=native` の OAuth 完了を処理する, the server shall Cookie 発行ではなく短命の `auth_code` を生成し `feedman://auth/callback` にリダイレクトする。
- When valid `auth_code` and PKCE `code_verifier` are posted to `/api/auth/token`, the server shall return Bearer access token, refresh token, token type, and `expires_in`.
- When `/api/auth/refresh` receives a valid refresh token, the server shall rotate the refresh token and return a new access token.
- When a previously rotated refresh token is reused, the server shall revoke the refresh token family and return an auth error.
- When an authenticated API request includes `Authorization: Bearer <access_token>`, the server shall resolve the same user ID context used by Cookie session authentication.
- When no Bearer token is present, the server shall continue to use the existing Cookie session middleware without behavior changes.
- When a user is deleted, the server shall remove that user's refresh tokens and auth codes.
- When existing Web login/logout flows are exercised, the server shall preserve current Cookie session behavior.

スコープ外:

- キーワードプッシュ通知 API。
- 既存 Web フロントのログイン UI 変更。
- Google の refresh token 管理方式の変更。

影響範囲のヒント:

- `internal/auth`
- `internal/middleware/session.go` 付近の認証 middleware
- `internal/handler/router.go`
- DB migration
- `internal/model` / `internal/repository`
- `design/SERVER.md` §1

制約・非機能要件:

- 既存 Cookie セッションは後方互換を維持する。
- refresh token は平文保存しない。
- PKCE S256 を必須にする。
- token / refresh endpoint には未認証 IP レート制限を適用する。

---

## Issue I1: SwiftUI iOS アプリのスケルトンを作成する

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: なし

背景・課題:

Feedman iOS はゼロから開始するため、以後の idd-codex 実装が機能単位で継続できる最小の Xcode プロジェクト、アーキテクチャ、テスト構成、開発ガイドが必要。

期待する挙動・ゴール:

- Xcode でビルドできる SwiftUI アプリが存在する。
- app shell, dependency container, environment config, design token, placeholder repository が配置される。
- idd-codex が以後の Issue で迷わない `AGENTS.md` とディレクトリ構成がある。

受入基準の候補:

- When the project is opened in Xcode, the app shall build for iOS Simulator with minimum deployment target iOS 16.
- When the app launches without credentials, the app shall show a login placeholder screen.
- When the app launches in preview/mock mode, the app shall show the drawer-based shell and mock timeline data.
- When tests are run, the project shall execute at least one unit test target successfully.
- When future issues need API work, the project shall expose protocol-based repositories and mock implementations.

スコープ外:

- Real OAuth login.
- Real API integration.
- Full visual parity with the prototype.

影響範囲のヒント:

- `Feedman.xcodeproj` or generated project structure
- `FeedmanApp`
- `AppEnvironment`
- `Core/API`
- `Core/Auth`
- `Features/*`
- `AGENTS.md`

---

## Issue I2: API models, APIClient, pagination, and error handling foundation

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: I1

背景・課題:

Feedman iOS の各画面は同じ API 契約、カーソルページネーション、エラー形式、Bearer 認証ヘッダを共有する。画面ごとに実装が散らばる前に、Codable 型と APIClient を固める必要がある。

期待する挙動・ゴール:

- `design/SPEC-iOS.md` §4 の API 型を Swift の `Codable` として表現する。
- APIClient が base URL、JSON decode、HTTP error、Feedman error body、401 refresh hook を扱う。
- Cursor pagination の共通 state が repository から利用できる。

受入基準の候補:

- When sample JSON for `ItemSummary` is decoded, the app shall preserve nullable favicon fields and RFC3339 strings.
- When the server returns `{ error: { code, message, category, action, details } }`, the API layer shall expose a typed Feedman error.
- When a paginated response includes `has_more=false`, the pagination state shall stop requesting additional pages.
- When a request receives 401 and refresh is available, the API client shall refresh credentials and retry the original request once.
- When refresh fails, the API client shall surface an auth-required state without infinite retry.

スコープ外:

- ASWebAuthenticationSession UI.
- Individual feature screens.

影響範囲のヒント:

- `Core/API`
- `Core/Models`
- `Core/Auth`
- Unit tests with JSON fixtures

---

## Issue I3: Google OAuth token login and secure token storage

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: I1, I2, S1

背景・課題:

iOS v1 の最初のゴールは Google ログイン後に横断タイムラインへ到達できること。ASWebAuthenticationSession、PKCE、custom scheme callback、Keychain 保存、refresh/revoke を一貫して実装する必要がある。

期待する挙動・ゴール:

- Google ログインボタンから native OAuth flow を開始できる。
- callback の `auth_code` を token endpoint で交換できる。
- refresh token は Keychain に保存され、access token は短命 token として扱われる。
- logout は revoke とローカル token 削除を行う。

受入基準の候補:

- When the user taps Google login, the app shall open `ASWebAuthenticationSession` with `flow=native` and PKCE challenge.
- When the app receives `feedman://auth/callback?auth_code=...`, the app shall exchange the code with `POST /api/auth/token`.
- When token exchange succeeds, the app shall persist the refresh token in Keychain and transition to the authenticated shell.
- When an access token expires, the app shall refresh it through `/api/auth/refresh`.
- When logout is requested, the app shall call `/api/auth/revoke`, clear local credentials, and return to login.

スコープ外:

- WebView Cookie login fallback.
- Push notification permission.

影響範囲のヒント:

- `Core/Auth`
- `TokenStore`
- `AuthRepository`
- URL scheme configuration
- `SafariServices` / `AuthenticationServices`

---

## Issue I4: Design system and shared SwiftUI components

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I1

背景・課題:

プロトタイプの見た目を SwiftUI で継続的に再現するには、色、余白、カード、favicon、star、hatebu、empty/loading/error などを共通部品化する必要がある。

期待する挙動・ゴール:

- Indigo accent のライト/ダーク theme token を提供する。
- data URL favicon と fallback letter avatar を扱える。
- card/list/sheet で使う共通 component がある。

受入基準の候補:

- When light and dark mode are toggled, the app shall apply Feedman theme colors consistently.
- When a favicon value is a `data:` URL, the favicon component shall decode and render it.
- When a favicon is null or invalid, the favicon component shall render a colored letter avatar.
- When an item is starred, the star control shall render a filled state and expose an accessible label.
- When a list is empty, the app shall render a reusable empty state component.

スコープ外:

- Feature-specific API calls.
- Keyword notification UI.

影響範囲のヒント:

- `DesignSystem`
- `SharedUI`
- `design/mobile/fm-data.jsx`
- `design/mobile/fm-ui.jsx`

---

## Issue I5: Drawer navigation and authenticated app shell

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I1, I4

背景・課題:

v1 の採用ナビゲーションは下タブではなく左ドロワー。iOS 標準 component ではないため、カスタム shell と画面 routing を早めに安定させる必要がある。

期待する挙動・ゴール:

- ハンバーガーで左ドロワーが開閉する。
- スクリムタップとドラッグ/スワイプで閉じられる。
- ドロワーから「すべての新着」「お気に入り」「フィード」「アカウント」へ移動できる。
- v1 では「キーワード通知」導線は表示しない。

受入基準の候補:

- When the user taps the menu button, the drawer shall slide in over the current screen with a scrim.
- When the user taps the scrim or swipes the drawer closed, the drawer shall close without changing the current view.
- When the user selects a feed, the app shall close the drawer and navigate to that feed's item list.
- When the app runs in v1, the drawer shall not expose keyword notification settings.
- When VoiceOver is enabled, drawer controls shall have meaningful labels.

スコープ外:

- Real subscriptions API integration.
- Keyword push implementation.

影響範囲のヒント:

- `AppShell`
- `Navigation`
- `Features/Subscriptions`
- `design/mobile/fm-screens.jsx`

---

## Issue I6: Cross-feed timeline with cursor pagination and refresh

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: I2, I4, I5

背景・課題:

横断タイムラインは Feedman iOS の主画面。`since_time` 固定、cursor pagination、既読/スターの楽観的更新、pull-to-refresh を正しく実装する必要がある。

期待する挙動・ゴール:

- `/api/items/cross-feed` を取得してカード一覧を表示する。
- 初回取得の `since_time` をセッション中固定する。
- 末尾表示で次 cursor を読み込む。
- pull-to-refresh で先頭から再取得する。

受入基準の候補:

- When the authenticated timeline first loads, the app shall request `/api/items/cross-feed` and render item cards.
- When the response contains `since_time`, the app shall reuse that value for subsequent pagination requests in the same session.
- When the last visible item appears and `has_more=true`, the app shall request the next page with `cursor`.
- When `has_more=false`, the app shall show an end-of-list state.
- When the user pulls to refresh, the app shall reload the timeline from the first page.
- When an item is read, the corresponding card opacity shall decrease.

スコープ外:

- Feed-specific fetch endpoint.
- Article detail content rendering.

影響範囲のヒント:

- `Features/Timeline`
- `ItemRepository`
- `design/SPEC-iOS.md` §5.1

---

## Issue I7: Article detail sheet, read state, star toggle, and Safari open

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: High（数日以内）

依存: I2, I4, I6

背景・課題:

記事タップ後の詳細シート、既読化、スター、元記事を開く操作は複数画面から共有される中核フロー。楽観的更新と失敗時の扱いを統一する必要がある。

期待する挙動・ゴール:

- item tap で `.medium` の詳細シートを開く。
- 詳細を開いた時点で既読化する。
- 元記事ボタンで SFSafariViewController を開き、既読化する。
- 一覧と詳細でスター状態が同期する。

受入基準の候補:

- When the user taps an item card, the app shall present a sheet with medium and large detents.
- When the detail sheet opens, the app shall call `PUT /api/items/{id}/state` with `is_read=true` and update local state optimistically.
- When the user taps the original article action, the app shall present `SFSafariViewController` for the item link.
- When the user toggles star in the list or detail sheet, the app shall call the state endpoint and keep visible item state consistent.
- If a read/star update fails, the app shall roll back optimistic state and show an error message.

スコープ外:

- Full offline HTML renderer.
- External browser setting.

影響範囲のヒント:

- `Features/ArticleDetail`
- `SharedUI/ArticleCard`
- `ItemRepository`
- `SafariServices`
- `design/mobile/fm-sheets.jsx`

---

## Issue I8: Feed-specific item list and subscription settings

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I2, I4, I5, I7

背景・課題:

フィード別の記事閲覧、未読/スター filter、手動 fetch、購読停止/再開/解除/間隔変更は RSS リーダーとして必須の管理機能。

期待する挙動・ゴール:

- `/api/subscriptions` のフィード一覧をドロワーに表示する。
- `/api/feeds/{id}/items?filter=all|unread|starred` を表示する。
- stopped/error feed は警告バナーを出す。
- 設定シートから fetch interval 変更、再開、解除ができる。
- pull-to-refresh は `POST /api/subscriptions/{id}/fetch` を呼ぶ。

受入基準の候補:

- When subscriptions load, the drawer shall show feed titles, unread counts, and stopped/error indicators.
- When the user selects a feed, the app shall fetch and render that feed's items.
- When the filter changes, the app shall reload items using the selected `filter` query.
- When a feed is stopped or in error, the feed screen shall show a status banner with a settings/resume affordance.
- When pull-to-refresh is used on a feed screen, the app shall call the subscription fetch endpoint.
- When the server returns `FEED_COOLDOWN`, the app shall show retry-after guidance.
- When interval settings are saved, the app shall call `PUT /api/subscriptions/{id}/settings`.
- When unsubscribe is confirmed, the app shall call `DELETE /api/subscriptions/{id}` and remove the feed locally.

スコープ外:

- OPML import/export.
- Feed URL edit UI.

影響範囲のヒント:

- `Features/Feeds`
- `Features/Subscriptions`
- `SubscriptionRepository`
- `design/SPEC-iOS.md` §5.2, §5.6

---

## Issue I9: Feed registration sheet

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I2, I4, I5

背景・課題:

ユーザーが新しい RSS/Atom を購読するには、URL 入力から feed auto-detection、重複/レート制限エラー処理までをアプリ内で完結させる必要がある。

期待する挙動・ゴール:

- ドロワーの plus から登録シートを表示する。
- URL 入力後に `POST /api/feeds` を呼ぶ。
- 成功時に購読一覧を更新する。
- 重複、URL 不正、レート制限をユーザーに説明する。

受入基準の候補:

- When the user opens feed registration, the app shall present a sheet with a URL input.
- When the user submits a valid URL, the app shall call `POST /api/feeds`.
- When registration succeeds, the app shall dismiss the sheet and refresh subscriptions.
- When the server reports duplicate subscription, the app shall show a non-destructive duplicate message.
- When the server reports rate limiting, the app shall show retry guidance.

スコープ外:

- OPML import.
- Manual feed metadata editing.

影響範囲のヒント:

- `Features/RegisterFeed`
- `FeedRepository`
- `design/mobile/fm-sheets.jsx`

---

## Issue I10: Starred list and global search

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I2, I4, I5, I7

背景・課題:

スター済み記事の再訪と横断検索は v1 スコープに含まれる。検索 result は `ItemSummary` と異なる型なので、混同せず実装する必要がある。

期待する挙動・ゴール:

- ドロワーのお気に入りから `/api/feeds/starred/items` を表示する。
- 検索ボタンから query 入力画面を表示し、`/api/items/search?q=&scope=global` を呼ぶ。
- 空 query ではサジェスト/空状態を表示する。
- 検索結果から記事詳細と元記事 open に進める。

受入基準の候補:

- When the user opens starred, the app shall fetch and render starred items across feeds.
- When a starred item is unstarred, the app shall update the starred list consistently.
- When the user submits a non-empty search query, the app shall call global search and render results.
- When search query is empty, the app shall not call the search endpoint and shall show an empty/suggestion state.
- When search results contain nullable `published_at` or `favicon_url`, the app shall render without crashing.

スコープ外:

- Feed-scoped search UI.
- Search history sync.

影響範囲のヒント:

- `Features/Starred`
- `Features/Search`
- `ItemSearchHit`

---

## Issue I11: Account screen, logout, and account deletion

対象 repo: `feedman-ios`

種別: 機能追加（新規）

優先度: Mid（今スプリント内）

依存: I2, I3, I5

背景・課題:

ログイン済みユーザーが自分のアカウント状態を確認し、ログアウトや退会を安全に実行できる必要がある。

期待する挙動・ゴール:

- アカウントシートで `/auth/me` のユーザー情報を表示する。
- ログアウトは token revoke と local credential clear を行う。
- 退会は二段確認後に `DELETE /api/users/me` を呼ぶ。

受入基準の候補:

- When the account sheet opens, the app shall show current user information from `/auth/me`.
- When the user logs out, the app shall revoke the refresh token, clear local credentials, and return to login.
- When the user requests account deletion, the app shall require confirmation before calling `DELETE /api/users/me`.
- When account deletion succeeds, the app shall clear local credentials and return to login.

スコープ外:

- Profile editing.
- Multi-account switching.

影響範囲のヒント:

- `Features/Account`
- `AuthRepository`
- `UserRepository`

---

## Issue I12: v1 integration hardening and release readiness

対象 repo: `feedman-ios`

種別: 既存機能の拡張・改善

優先度: Mid（今スプリント内）

依存: I3, I6, I7, I8, I9, I10, I11

背景・課題:

機能単位の実装後、ローディング/空/エラー、アクセシビリティ、Dynamic Type、主要フローの結合テストを揃えないと v1 として安定しない。

期待する挙動・ゴール:

- v1 の受け入れ基準を通しで検証できる。
- 主要画面が loading / empty / error / retry を持つ。
- Dynamic Type と VoiceOver の基本対応ができている。
- README に開発/実行/設定方法がまとまっている。

受入基準の候補:

- When the API is slow, each list screen shall show a loading state.
- When the API returns a recoverable error, each screen shall show an error state with retry where appropriate.
- When Dynamic Type is increased, primary controls shall remain usable without text overlap.
- When VoiceOver is enabled, primary navigation, star, open link, and sheet controls shall have accessible labels.
- When a developer follows README setup steps, the app shall build and run in Simulator.
- When v1 smoke tests are run, login-to-timeline, item detail, star, feed filter, and logout flows shall pass.

スコープ外:

- App Store submission.
- Push notification feature.
- Offline full-content cache.

影響範囲のヒント:

- All features
- README
- Test targets

---

## Issue P1: キーワードプッシュ通知 API と iOS UI を実装する（次フェーズ）

対象 repo: `feedman` + `feedman-ios`

種別: 機能追加（新規）

優先度: Low（時間があれば）

依存: v1 release

背景・課題:

ユーザーが登録したキーワードを新着記事タイトルに照合し、一致時に端末へ通知する機能は次フェーズの差別化機能。ただしサーバー API、device registration、APNs/FCM、iOS permission、deep link が絡むため v1 からは外す。

期待する挙動・ゴール:

- サーバーが device と keyword CRUD を提供する。
- 新着 fetch 時に keyword match を検出し、重複なく push job を送る。
- iOS が通知許可、APNs token 登録、keyword 管理 UI、通知 deep link を扱う。

受入基準の候補:

- When an iOS device grants notification permission, the app shall register its push token with `/api/devices`.
- When a user creates a keyword, the server shall store it and return it in `/api/keywords`.
- When a newly fetched item title matches an enabled keyword, the server shall enqueue one notification per keyword/item pair.
- When the user taps a notification, the iOS app shall open the corresponding article detail via deep link.

スコープ外:

- v1 release scope.
- Body/content keyword matching.
- OPML integration.

影響範囲のヒント:

- `design/SERVER.md` §2
- `design/SPEC-iOS.md` §7
- iOS `UNUserNotificationCenter`
