# Issue #36 SFSafariViewController original article opener 要件定義

## 概要

Issue #36 は Parent: #7 の子 Issue として、記事詳細 sheet の「元記事を開く」action を iOS 標準の `SFSafariViewController` 表示へ接続し、元記事を開く操作を既読化へ反映する責務を扱う。

Issue 本文のゴールは "Original article links open inside SFSafariViewController and mark items read." である。受入候補として、元記事 action tap 時に `SFSafariViewController` が item link を表示すること、元記事 open 時に item が既読化されること、URL が invalid な場合に回復可能エラーを表示することが示されている。

Issue コメントでは、依存先 #35 は `codex-staged-for-release` 状態のため `develop` には merge 済みとして依存解消済み扱いで進める、という人間回答がある。したがって #36 は #35 の ArticleDetail sheet と callback 境界を前提にできる。ただし、作業 branch に #35 の成果物が存在しない場合は推測で補完せず確認する。

## 参照仕様

- Issue #36 本文と `gh issue view 36 --comments` の既存コメント。
- `design/SPEC-iOS.md` §2、§4.2、§5.1、§5.4、§6、§10。
- `design/SERVER.md` §1 の Bearer 認証前提と既存 API 互換要件。
- `docs/specs/35-article-detail-sheet-ui/requirements.md` / `impl-notes.md`。
- 既存 `Feedman/Features/ArticleDetail/ArticleDetailSheet.swift` / `ArticleDetailViewModel.swift`。
- 既存 `Feedman/Features/AppShell/AppShellState.swift` / `RootView.swift`。

## 前提

- #35 により `ArticleDetailSheet` / `ArticleDetailViewModel` / `ArticleDetailSheetInput` が存在し、親画面から `onOpenOriginal(URL)` callback を受け取る。
- #35 実装ノートでは、「元記事を開く」は Safari を起動せず親 callback 経由の placeholder に留め、`SFSafariViewController` presenter、Safari 起動後の既読化 orchestration、global state sync はスコープ外として残されている。
- 現在の `RootView` は article detail sheet の `onOpenOriginal` を SwiftUI `openURL` へ直結している。#36 ではこの経路を `SFSafariViewController` 表示へ置き換える、または同等の app-shell presenter 経路へ接続する。
- 現在の Timeline / Feed の card selection は `RootView` で no-op callback になっている箇所が残る。#36 は ArticleDetail からの open-original flow を中心に扱い、一覧 tap の detail 接続拡張は本 Issue の必須範囲にしない。

## スコープ

- ArticleDetail sheet の「元記事を開く」action から渡される http / https URL を `SFSafariViewController` でアプリ内表示する。
- `SFSafariViewController` を SwiftUI から提示するための薄い presenter / wrapper / presentation state を追加する。
- 元記事 open 操作時に `ItemRepository.updateItemState` へ `is_read: true` の partial update を要求する。
- 元記事 open 操作時の既読化は `is_starred` を変更しない。
- URL が missing / invalid / non-http(s) の場合、クラッシュせず回復可能エラーを表示する。
- 認証切れや read marking 失敗は、既存の auth-required / toast / banner 境界でユーザーに表示可能にする。
- Focused XCTest または coordinator unit test で Safari presentation intent、read marking request、invalid URL error を検証する。

## スコープ外

- 外部ブラウザ preference setting、`UIApplication.open` への切替設定、既定ブラウザ選択 UI。
- detail / list / starred / search をまたぐ global state sync の大規模拡張、optimistic cross-screen sync、失敗時 rollback の汎用 store 新設。
- Timeline / Feed / Starred / Search の新規画面実装、または一覧 tap から detail sheet へつなぐ広範な bridge 実装。
- Feed unread count の更新、一括既読、background sync、server sync endpoint。
- サーバー API 変更、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、他 Issue の確定済み `docs/specs/*` の変更。
- WebView Cookie login fallback、キーワード通知 UI、feed-scoped search UI、OPML、オフライン全文 cache。
- PR 作成、reviewer / project-manager 起動、コミット。

## 要件

### Requirement 1: SFSafariViewController presentation

**Objective:** As an 記事詳細閲覧者, I want 元記事をアプリ内 Safari で開ける, so that Feedman の文脈を保ったまま本文を読める

#### Acceptance Criteria

1. When the user activates「元記事を開く」from ArticleDetail with a valid http or https URL, the app shall present `SFSafariViewController` for that URL.
2. When presenting the original article, the implementation shall use `SafariServices.SFSafariViewController` rather than SwiftUI `openURL` or `UIApplication.open` as the primary behavior for this flow.
3. When `SFSafariViewController` is dismissed, the app shall return to the prior Feedman UI without clearing unrelated app shell route state.
4. When another original article is opened after dismissal, the presenter shall show the newly requested URL and shall not reuse stale URL state.
5. When Safari presentation is active, account, feed registration, subscription settings, or article detail presentations shall not overwrite the Safari presentation ambiguously.
6. The implementation shall not add an external browser preference or browser selection setting in this Issue.

### Requirement 2: ArticleDetail open-original routing

**Objective:** As a Developer, I want #35 の callback 境界を使って Safari 表示を接続できる, so that ArticleDetail が platform presentation と repository orchestration を抱え込まない

#### Acceptance Criteria

1. When ArticleDetail emits `onOpenOriginal(URL)`, AppShell or an equivalent thin coordinator shall receive the URL and coordinate Safari presentation.
2. When coordinating open-original, the coordinator shall retain the selected item id or equivalent context needed to request read marking for the same article.
3. When the ArticleDetail loaded detail has a valid `link`, that loaded detail URL shall be preferred over any earlier summary URL.
4. If only summary URL is available before detail loading completes, the open-original affordance may use the valid summary URL, but it shall still avoid opening invalid or non-http(s) URLs.
5. When the open-original action is unavailable because no valid URL exists, the UI shall prevent accidental presentation and shall surface a recoverable error if the user can still attempt the action.
6. The ArticleDetail View shall not construct `URLSession` requests, read Keychain directly, or own token refresh logic for the open-original flow.
7. The implementation should reuse #35 ArticleDetail state and callback types where practical instead of introducing a duplicate detail feature.

### Requirement 3: Read marking on original article open

**Objective:** As a user, I want 元記事を開いた記事が既読として扱われる, so that 本文閲覧が Feedman の読了状態に反映される

#### Acceptance Criteria

1. When original article opening is requested for an item, the app shall request read marking through `ItemRepository.updateItemState`.
2. When read marking is requested for original article open, the request shall be a partial update equivalent to `is_read: true` and shall not force `is_starred`.
3. When the item was already marked read by #35 sheet-open behavior, the open-original flow may skip a duplicate mutation or send an idempotent `is_read: true` request, but it shall not mark the item unread.
4. When the original article opens successfully and read marking succeeds, the app shall expose the confirmed read state through the existing `ItemStateChange` or equivalent local state boundary where already available.
5. If read marking fails after Safari presentation is requested, the app shall not close Safari automatically and shall surface a non-blocking error when the user returns or where an existing toast / banner boundary is available.
6. If auth is required for read marking, the app shall use the existing auth-required handling boundary rather than presenting the operation as successful.
7. The implementation shall not introduce a new item state API or require the server to return an updated item body for mutation success.

### Requirement 4: Invalid URL recovery

**Objective:** As a Feedman user, I want 壊れたリンクでもアプリが落ちずに回復できる, so that 記事詳細から安全に操作を続けられる

#### Acceptance Criteria

1. When the raw article link is missing, blank, malformed, or has a non-http(s) scheme, the app shall not present `SFSafariViewController`.
2. When an invalid URL is detected before the user taps, the open-original affordance should be disabled, hidden, or otherwise communicated as unavailable without layout breakage.
3. If the user can trigger open-original despite an invalid URL state, the app shall show a recoverable Japanese error message equivalent to「元記事のURLを開けませんでした」.
4. When invalid URL recovery is shown, the ArticleDetail sheet shall remain usable and dismissible.
5. When invalid URL recovery is shown, the app shall not request read marking for an item whose original article was not opened because of invalid URL.
6. When the invalid URL comes from API data, tests shall use dummy URLs and shall not log private article data.

### Requirement 5: Error handling and user feedback

**Objective:** As an iOS user, I want Safari 表示と既読化の失敗を理解できる, so that 操作結果を誤解せずに戻れる

#### Acceptance Criteria

1. If Safari presentation cannot be prepared for a valid URL, the app shall show a recoverable error and shall keep the current ArticleDetail / AppShell state usable.
2. If read marking fails, the app shall show a non-blocking Japanese message equivalent to「既読状態を保存できませんでした」.
3. If auth is required, the app shall show the existing re-login required feedback and shall not silently swallow the failure.
4. When an error message is shown, it shall not permanently cover Safari dismissal, ArticleDetail dismissal, or primary navigation controls.
5. When shared toast / banner primitives are available, the implementation should use them instead of creating an unrelated feedback style.
6. The implementation shall not expose raw backend error payloads, access tokens, refresh tokens, or `Authorization` header values in user-visible messages or logs.

### Requirement 6: Tests and verification

**Objective:** As a QA / Developer, I want 元記事 open flow を小さく検証できる, so that Safari 表示と既読化の regression を検出できる

#### Acceptance Criteria

1. When a valid http URL is passed to the open-original coordinator, tests shall verify Safari presentation intent is produced for that URL.
2. When a valid https URL is passed to the open-original coordinator, tests shall verify Safari presentation intent is produced for that URL.
3. When an invalid URL or unsupported scheme is passed, tests shall verify no Safari presentation intent is produced and recoverable error state is exposed.
4. When original article open is requested with valid item context, tests shall verify `ItemRepository.updateItemState` receives `isRead == true` and `isStarred == nil`.
5. When read marking succeeds, tests shall verify an `ItemStateChange` or equivalent confirmed read signal is emitted where the existing boundary supports it.
6. When read marking fails, tests shall verify user-presentable failure is exposed and Safari presentation state is not cleared as a side effect.
7. When auth is missing or expired, tests shall verify auth-required feedback is routed through the existing boundary.
8. Tests shall use mock repositories, dummy item ids, and dummy URLs only, without real network, real Keychain, real OAuth, or personal article data.
9. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Architecture

1. The implementation shall support iOS 16+ SwiftUI.
2. The Safari presenter shall use `SafariServices` and a SwiftUI-compatible wrapper or coordinator appropriate for the existing app shell.
3. The implementation shall follow MVVM + Repository and keep Views away from direct `URLSession`、Keychain、request body encoding、and Bearer token refresh details.
4. UI-facing coordinator / ViewModel state shall be `@MainActor` where required.
5. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Scope control

1. The implementation shall remain within Issue #36 の SFSafariViewController original article opener responsibility.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not introduce new server API contracts or rely on prototype mock JSON shapes.
4. The implementation shall not add external browser preference settings or a broad browser abstraction.
5. The implementation shall not add global state sync infrastructure beyond the minimal confirmed read signal already available in AppShell / ArticleDetail.

### NFR 3: Privacy and security

1. The implementation shall not commit real tokens, Secret、個人情報、または実ユーザーの記事データ。
2. Logs shall not include access tokens, refresh tokens, `Authorization` header values, or full private article content.
3. Error messages shall be concise Japanese user-facing messages and shall avoid leaking internal server details.
4. Repository errors shall not be swallowed silently when they affect read marking or Safari presentation feedback.

## 実装境界メモ

- `ArticleDetailSheet` already validates loaded `link` into `URL?` and exposes `onOpenOriginal(URL)`. #36 should extend the callback context or AppShell state only as much as needed to know the item id for read marking.
- If changing `onOpenOriginal` from `(URL) -> Void` to a small request type is simpler, that type should contain only item id and validated URL, not article content or unrelated metadata.
- `RootView` currently uses `@Environment(\.openURL)` for article detail open-original. #36 should replace this path for ArticleDetail with `SFSafariViewController` presentation while avoiding broad replacement of every external link flow unless the same narrow coordinator already owns it.
- #35 already marks read on sheet open. #36 read marking on original open should be idempotent and should not create duplicate user-visible failure noise when the item is already confirmed read.
- Global state sync and rollback are owned by #37. #36 may emit confirmed read changes through existing `ItemStateChange`, but should not build a generic synchronization store.
- Search result bridge behavior is covered by #47. #36 should not expand into search-specific detail mapping.
