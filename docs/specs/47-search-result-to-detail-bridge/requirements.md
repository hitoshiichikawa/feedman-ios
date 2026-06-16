# Issue #47 Search result to detail bridge 要件定義

## 概要

Issue #47 は Parent: #10 の子 Issue として、#46 で追加された横断検索結果カードの action 境界を、#35 で追加された記事詳細 sheet と既存の元記事 open flow に接続する。
ゴールは、検索結果をタップしたときに選択 item の記事詳細 sheet を開き、`ItemSearchHit` が `ItemSummary` と同一 field を持たない場合でも安全に summary 表示または詳細取得へ委譲し、元記事 open 時の既読 / スター状態を検索結果と詳細 sheet の間で矛盾させないことである。

Issue 本文では、期待する挙動として "Search results can open article detail and original article flow consistently." が示されている。
受入基準候補は、検索結果タップで detail sheet を開くこと、`ItemSummary` に必要な field が検索結果にない場合は detail fetch または安全な mapping を行うこと、元記事 open 時も read / star state handling を整合させることである。

Issue コメントでは、依存 Issue #35 / #46 が `staged-for-release` として解消済みであり、edit path は `Feedman/Features/Search/` と `Feedman/Features/ArticleDetail/` とされている。
したがって本 Issue は両 Issue の成果を前提に進め、未接続の app shell / coordinator 配線を実装対象とする。

## 参照仕様

- Issue #47 本文と `gh issue view 47 --comments` の既存コメント。
- `design/SPEC-iOS.md` §4.2, §4.3, §5.1, §5.3, §5.4, §6。
- `design/SERVER.md` は本 Issue 用の検索 / 詳細 API 追加契約を持たないため、API 契約は `design/SPEC-iOS.md` を正本とする。
- `docs/specs/35-article-detail-sheet-ui/requirements.md` / `impl-notes.md`。
- `docs/specs/46-global-search-repository-and-screen/requirements.md` / `impl-notes.md`。

## 前提

- #35 により `ArticleDetailSheet` / `ArticleDetailViewModel` / `ArticleDetailSheetInput` が存在し、`ItemRepository.itemDetail(id:accessToken:)` と `updateItemState` により詳細取得、open 時の既読化、sheet-local star toggle を扱える。
- #35 の実装ノートでは、Safari 実起動、検索 / 一覧 / 詳細をまたぐ global state sync、Safari 起動後の既読化 orchestration は未対応として残っている。
- #46 により `GlobalSearchView` / `GlobalSearchViewModel` / `SearchResultRowDescriptor` が存在し、検索結果カードは `onSelectItem` と `onOpenLink` callback 境界を持つ。
- #46 の実装ノートでは、検索結果 card tap は callback 境界まで、open-link は AppShell から SwiftUI `openURL` へ委譲する状態であり、article detail coordinator / sheet presentation と SFSafariViewController presentation 境界は未接続である。
- `ItemSearchHit` は `ItemSummary` とは別 struct であり、`published_at`、`favicon_url`、`is_date_estimated`、`is_read`、`is_starred` は nullable で、`hatebu_fetched_at` を持たない。

## スコープ

- 検索結果カードの tap を、選択 item id に対応する `ArticleDetailSheet` 表示へ接続する。
- 検索結果から detail sheet へ渡す summary input を、`ItemSearchHit` の nullable field を許容する形で安全に構築する。
- 検索結果に不足している field は、detail sheet の `GET /api/items/{id}` 相当の詳細取得を正本として補完する。
- 検索結果から元記事を開く action を、既存の外部リンク open 境界へ接続し、少なくとも read marking の整合に必要な state update を repository 経由で行う。
- 検索結果 detail sheet 内の star toggle 後、検索画面に戻ったときに同じ item の visible star state が誤ったまま固定されないようにする。
- 認証切れ、詳細取得失敗、既読化失敗、無効 URL をユーザーに表示可能な状態として扱う。
- Focused XCTest で検索結果 tap、summary mapping、detail sheet presentation、元記事 open と read marking、star state reflection の主要 state transition を検証する。

## スコープ外

- Search history、ranking、検索履歴永続化、検索候補 API。
- Feed-scoped search UI と `scope=feed` 画面導線。
- サーバー API 変更、`design/SPEC-iOS.md` / `design/SERVER.md` 変更。
- `ItemSearchHit` を `ItemSummary` に統合する API model 変更。
- キーワードプッシュ通知 UI、通知 deep link、OPML、オフライン全文 cache。
- Star 一覧、フィード別一覧、横断タイムライン全体の global state store 新設。
- SFSafariViewController 以外の完全外部ブラウザ設定 UI。
- PR 作成、reviewer / project-manager 起動、コミット。

## 受入基準（EARS）

### Requirement 1: Search result tap opens detail sheet

**Objective:** As a Feedman user, I want 検索結果をタップして記事詳細を開ける, so that 検索で見つけた記事を一覧文脈からすぐ確認できる

1. When a search result is tapped, the app shall present `ArticleDetailSheet` for the selected item id.
2. When the detail sheet is presented from search, it shall use the #35 article detail boundary instead of duplicating detail UI inside `Feedman/Features/Search/`.
3. When a different search result is tapped after dismissing the sheet, the app shall present the newly selected item and shall not show stale detail content as current.
4. When the selected item id is empty or invalid at the UI boundary, the app shall avoid presenting a broken sheet and shall surface a recoverable error or ignore the action deterministically.
5. When the user dismisses the detail sheet, the app shall return to the search screen without clearing the active query or current search results unless the user explicitly clears them.
6. When the search route is not active anymore, pending detail presentation state shall not unexpectedly reopen on unrelated routes.

### Requirement 2: Safe mapping from ItemSearchHit to detail input

**Objective:** As a Developer, I want `ItemSearchHit` を安全に detail input へ渡せる, so that nullable field や `ItemSummary` との差分で UI が壊れない

1. When constructing summary data for `ArticleDetailSheetInput`, the app shall map `ItemSearchHit.id`, `feedTitle`, `faviconURL`, `title`, `summary`, `link`, `publishedAt`, `isDateEstimated`, `isStarred`, `hatebuCount`, and `author` only when each value is available.
2. When `ItemSearchHit.publishedAt` is nil, the app shall pass nil summary date and shall not synthesize a fake timestamp.
3. When `ItemSearchHit.isDateEstimated` is nil, the app shall pass nil estimated-date state and shall let detail data become the source of truth after fetch.
4. When `ItemSearchHit.isStarred` is nil, the app shall avoid treating the item as definitely unstarred in mutation logic before detail data is loaded.
5. When `ItemSearchHit` lacks `hatebu_fetched_at`, the app shall pass nil fetched-at state and shall not invent a fetched timestamp.
6. When `ItemSearchHit.faviconURL` is nil, invalid, or a `data:` URL, the app shall preserve the existing favicon component behavior and shall not pass a `data:` URL to `AsyncImage(url:)`.
7. When result summary data is incomplete, the detail sheet shall fetch `GET /api/items/{id}` through `ItemRepository.itemDetail(id:accessToken:)` and shall use the returned `ItemDetail` as the source of truth.

### Requirement 3: Detail fetch, read marking, and error behavior

**Objective:** As a Feedman user, I want 検索結果から開いた詳細でも既読化と詳細取得が通常の詳細 sheet と同じように動く, so that entry point によって状態が変わらない

1. When detail sheet opens from a search result, it shall request read marking through `ItemRepository.updateItemState` with `is_read: true` and without forcing `is_starred`.
2. When detail data is loaded, the sheet shall display `ItemDetail` values over any initial search summary values.
3. When detail loading is in progress, the sheet shall show loading state while retaining any safe summary preview supplied from the search result.
4. If detail loading fails, the sheet shall show recoverable error state with retry and shall keep the search screen state intact behind the sheet.
5. If read marking fails, the sheet shall remain usable and shall surface a non-blocking failure rather than dismissing automatically.
6. If auth is required during detail fetch or read marking, the app shall use the existing auth-required handling boundary rather than presenting the failure as an empty search result.
7. The implementation shall not perform direct `URLSession` calls from View or Search ViewModel for detail fetch or read marking.

### Requirement 4: Original link open from search remains consistent

**Objective:** As a Feedman user, I want 検索結果から元記事を開いても既読状態が反映される, so that 詳細 sheet 経由と direct open 経由で読了状態が一致する

1. When the user activates the open-link control on a search result, the app shall open the hit's original link through the existing external article opening boundary.
2. When original link opens from a search result, the app shall request `is_read: true` for the selected item through `ItemRepository.updateItemState`.
3. When the open-link control is activated inside a tappable result card, the open-link action shall not also trigger the card detail action.
4. If the link is not a valid http or https URL, the open-link affordance shall be disabled or no-op without crashing.
5. If read marking for open-link fails, the app shall still keep the open action result deterministic and shall surface a non-blocking error where existing toast / error boundary is available.
6. When read marking succeeds after direct open, the visible search result state should reflect read status if the current search model exposes it; otherwise it shall not present a contradictory unread-only affordance.
7. The implementation shall not add a search-specific item-state API; it shall use the existing item state repository boundary.

### Requirement 5: Star state consistency between search and detail

**Objective:** As a Feedman user, I want 検索結果から開いた詳細で star を変更しても戻った検索結果が矛盾しない, so that 同じ記事の状態を信頼できる

1. When the user toggles star in a detail sheet opened from search, the mutation shall be performed by the #35 article detail ViewModel through `ItemRepository.updateItemState`.
2. When star mutation succeeds, the search screen should update the matching visible hit's `isStarred` value if that hit exposed `is_starred` in the original result.
3. When the original search hit did not expose `is_starred`, the search screen shall avoid showing a newly invented persistent star state unless it has a confirmed value from detail or mutation result.
4. If star mutation fails, the search screen shall not apply a successful star state optimistically as final.
5. When the user reopens the same item from search after a star change, the detail sheet shall fetch fresh detail or use confirmed current state so that stale search summary does not override the loaded detail.
6. The implementation shall keep star updates scoped to visible search results and the current detail sheet; it shall not introduce broad cross-feature state synchronization in this Issue.

### Requirement 6: App shell and presentation coordination

**Objective:** As a Developer, I want AppShell が search と article detail presentation を明示的に調停する, so that feature 内部で routing 責務が重複しない

1. When `GlobalSearchView.onSelectItem` fires, AppShell or an equivalent coordinator shall store selected article detail state and present the active sheet via the existing `.sheet` presentation path.
2. When `GlobalSearchView.onOpenLink` fires, AppShell or an equivalent coordinator shall coordinate external link opening and read marking for the selected item.
3. When an article detail sheet is active, other AppShell presentations such as account or feed registration shall not overwrite it ambiguously.
4. When AppShell dismisses a detail sheet, it shall clear only the active detail presentation state needed for dismissal.
5. The implementation shall keep primary edits within `Feedman/Features/Search/`, `Feedman/Features/ArticleDetail/`, and the existing app shell coordination boundary required to connect them.
6. The implementation shall not move search repository, item repository, or article detail networking logic into AppShell.

### Requirement 7: Accessibility and visual behavior

**Objective:** As an iOS user, I want 検索から開いた詳細と元記事 action がアクセシブルに動く, so that VoiceOver や Dynamic Type でも主要操作を迷わない

1. When a search result card is tappable, it shall expose an accessible action or label for opening article detail.
2. When the open-link control is available, it shall expose an accessible label distinct from opening detail.
3. When the detail sheet opens from search, it shall preserve #35 medium / large detent behavior, accessible dismiss, star, retry, and open-original controls.
4. When search summary text, title, or metadata is long, card content shall not overlap open-link or star controls.
5. When Dynamic Type is enabled, search result action controls and detail sheet footer controls shall preserve usable touch targets.
6. The UI shall not expose v1 scope-out keyword notification UI, feed-scoped search, search history, or ranking controls as part of this bridge.

### Requirement 8: Tests and verification

**Objective:** As a QA / Developer, I want bridge behavior を小さく検証できる, so that 検索、詳細、元記事 open の接続が regression しにくい

1. When a search result is selected, tests shall verify the coordinator creates article detail presentation for the selected item id.
2. When an `ItemSearchHit` with nullable fields is selected, tests shall verify summary mapping preserves nil values and does not synthesize date, star, or hatebu fetched state.
3. When detail sheet opens from a selected search result, tests shall verify `ItemRepository.itemDetail` and read marking are invoked through existing repository boundaries.
4. When detail loading fails, tests shall verify search state remains available and retry is possible from the sheet.
5. When open-link is activated from a search result, tests shall verify link opening and read marking are requested without also selecting the card.
6. When the link is invalid, tests shall verify no crash and no invalid external open request.
7. When star is toggled in a detail sheet opened from search, tests shall verify successful state reflection for the matching visible search hit where a confirmed state exists.
8. When star or read mutation fails, tests shall verify final visible state is deterministic and user-presentable failure is available.
9. While macOS/Xcode test execution is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or report why it could not be run.

## 非機能要件

### NFR 1: Architecture

1. The implementation shall follow MVVM + Repository and shall keep View code free of `URLSession`、Keychain、request encoding、Bearer token refresh details.
2. The implementation shall use Swift Concurrency (`async` / `await`) for repository calls.
3. `@MainActor` が必要な ViewModel / coordinator state は明示する。
4. Swift の型名、識別子、ファイル名は English にする。
5. The implementation shall prefer existing #35 / #46 types and callbacks over new duplicate abstractions.

### NFR 2: Scope control

1. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
2. The implementation shall not introduce new server API contracts or rely on prototype mock JSON shapes.
3. The implementation shall not broaden into search history、ranking、feed-scoped search、keyword notification、or global state-store design.
4. The implementation shall keep changes limited to the bridge needed for Issue #47.

### NFR 3: Error handling and privacy

1. The implementation shall map repository errors to UI-presentable state and shall not silently swallow detail fetch, read marking, or star mutation failures.
2. The implementation shall not log access tokens, refresh tokens, `Authorization` header values, search query personal data beyond debug-safe diagnostics, or response content containing personal data.
3. Tests shall use mock repositories and dummy item ids / URLs only.

## 実装境界メモ

- Search result selection should pass an `ArticleDetailSheetInput` containing the selected id and safe `ArticleDetailSummary` converted from `ItemSearchHit`.
- `ItemSearchHit.faviconURL` maps to `ArticleDetailSummary.feedFaviconURL`; `ItemSearchHit` has no `hatebuFetchedAt`, so that summary field remains nil.
- `ItemSearchHit.publishedAt` is optional and remains optional through summary mapping.
- `ItemSearchHit.isRead` may be useful for search card opacity, but `ArticleDetailSummary` currently does not carry read state. The detail sheet's fetched `ItemDetail` and read marking result are the source of truth.
- Direct original-link open from a search row currently needs item id as well as URL. If the existing callback only passes `URL`, the implementation should extend the callback or descriptor boundary to pass selected item identity without causing card tap duplication.
- `RootView` currently passes no-op `onSelectItem` for `GlobalSearchView`; #47 should replace that no-op with presentation state wiring.

## 確認事項

- SFSafariViewController presentation boundary is not yet visible in #46 implementation notes. If no existing boundary is available at implementation time, use the current external open boundary consistently and keep a narrow follow-up note for SFSafari replacement rather than building a broad browser abstraction.
- The current `ArticleDetailViewModel` marks read before loading detail. If missing access token occurs, it may set failure before detail loading. Implementation should preserve deterministic auth-required handling and avoid presenting search empty state for this case.
- Search visible-hit state updates after detail star/read changes should remain local and minimal. A shared global item state store is outside this Issue.
