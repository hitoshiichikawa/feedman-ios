# Issue #35 Article detail sheet UI 要件定義

## 背景

Issue #35 は Parent: #7 の子 Issue として、記事一覧などから選択した記事を medium / large detent の記事詳細 sheet で表示する UI を定義する。
ゴールは、source、title、metadata、content preview、actions を含む sheet を表示し、sheet を開いた時点で既読化 request を行うことである。

`design/SPEC-iOS.md` §5.4 では、記事詳細は `.sheet` + `.presentationDetents([.medium, .large])` で実装し、medium を preview、large を「続きを読む」相当として扱うこと、source 行・title・はてブ / star・本文 preview を表示すること、footer 固定 action として「元記事を開く」と star を置くこと、開いた時点で `PUT /api/items/{id}/state {is_read:true}` を行うことが定義されている。
ただし Issue #35 本文では Safari opening と global state sync がスコープ外であるため、本 Issue は Safari 実起動と一覧 / 詳細 / スター一覧をまたぐ同期までは扱わない。

Issue コメントでは、追加の人間決定事項はなく、Path Overlap Checker の edit path は `Feedman/Features/ArticleDetail/` とされている。

## 依存と実装可否

- Depends on: #27, #34。
- #27 は PR #69 として `develop` へ merge 済み、Issue は `codex-staged-for-release` で `main` 到達待ちである。#35 実装時は #27 の `FeedmanSheetShell`、`feedmanSheet`、loading / error / toast primitive を利用できる前提だが、作業 branch に該当変更が存在することを確認する。
- #34 は PR #77 として `develop` へ merge 済み、Issue は `codex-staged-for-release` で `main` 到達待ちである。#35 実装時は #34 の `ItemRepository.itemDetail(id:accessToken:)` と `updateItemState(id:request:accessToken:)` を利用できる前提だが、作業 branch に該当変更が存在することを確認する。
- 両依存 Issue は GitHub 上では OPEN のままなので、`main` 到達前の release 運用上の OPEN と、実装 dependency の未完了を混同しない。実装開始時に対象 branch が `develop` 相当の依存実装を含まない場合は、実装へ進まず確認事項としてエスカレーションする。

## 参照仕様

- Issue #35 本文と `gh issue view 35 --comments` の既存コメント。
- `docs/specs/27-reusable-loading-empty-error-toast-and-s/requirements.md` / `impl-notes.md`。
- `docs/specs/34-item-detail-and-state-repository-methods/requirements.md` / `impl-notes.md`。
- `docs/specs/26-shared-article-metadata-controls/requirements.md` / `impl-notes.md`。
- `design/SPEC-iOS.md` §4.2, §4.3, §4.4, §5.1, §5.4, §6, §10。
- `design/SERVER.md` §1 の Bearer 認証前提と既存 API 互換要件。
- `design/Feedman iPhone.html` と `design/mobile/fm-sheets.jsx` の `FMDetailSheet` は視覚参考。ただし React prototype の mock data 形や独自 gesture は API / 実装契約として扱わない。

## スコープ

- `Feedman/Features/ArticleDetail/` 配下に Article detail sheet の SwiftUI View / ViewModel または同等の UI state coordinator を追加する。
- 記事 id と一覧側から渡された最低限の summary 情報を受け取り、`ItemRepository` から `ItemDetail` を取得して詳細内容を表示する。
- `.sheet` と `.presentationDetents([.medium, .large])` または #27 の `feedmanSheet` / `FeedmanSheetShell` を利用し、medium / large detent を提供する。
- source 行、title、published metadata、author、はてブ数、star 状態、content preview を表示する。
- content が長い場合、sheet 内の preview を scroll 可能または展開可能にし、header / footer / action と重ならないようにする。
- sheet を開いた時点で #34 の `updateItemState` により `ItemStateUpdateRequest(isRead: true, isStarred: nil)` 相当の既読化 request を行う。
- detail loading / error state は #27 の shared primitives を使って表示し、retry 可能な導線を用意する。
- star action は detail sheet 内でユーザーが状態を変更できる UI を提供し、#34 の partial state update を呼べる境界までを扱う。

## スコープ外

- SFSafariViewController の実起動、Safari presenter、外部記事を開く routing。
- 「元記事を開く」押下後の read marking と Safari opening の一連の orchestration。
- 一覧 / 詳細 / スター一覧 / 検索結果をまたぐ global state sync、optimistic cross-screen sync、失敗時 rollback。
- 横断タイムライン、フィード別一覧、スター一覧、検索結果の article card 組み込み。
- feed-scoped search UI、キーワードプッシュ通知 UI、OPML、オフライン全文 cache。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md`、他 Issue の確定済み `docs/specs/*` の変更。

## 要件

### Requirement 1: Sheet presentation

**Objective:** As an 記事一覧ユーザー, I want 記事をタップしたら部分 sheet で詳細 preview を見られる, so that 一覧の文脈を保ったまま記事内容を確認できる

#### Acceptance Criteria

1. When an item is opened, the article detail sheet shall present with medium and large detents.
2. When the sheet is first presented, the medium detent should act as the preview presentation defined by `design/SPEC-iOS.md` §5.4.
3. When the user expands the sheet to the large detent, the detail content shall remain readable and shall not require a separate full-screen route.
4. When the user dismisses the sheet, the ArticleDetail UI state shall clear the selected item / detail loading state enough that reopening another item does not show stale content as the current article.
5. When the sheet is presented, it shall use #27 shared sheet shell behavior where practical instead of introducing a separate custom bottom-sheet gesture engine.
6. When Dynamic Type or narrow device width increases content height, the sheet shall keep the dismiss affordance reachable and avoid title / metadata / action overlap.

### Requirement 2: Detail loading and data source

**Objective:** As an ArticleDetail 実装者, I want `ItemRepository` 経由で `content` を含む詳細を読み込める, so that View が APIClient や URLSession を直接扱わない

#### Acceptance Criteria

1. When the sheet needs full detail data for an item id, the ViewModel shall request `ItemRepository.itemDetail(id:accessToken:)`.
2. When detail loading is in progress, the sheet shall show a loading state using #27 shared loading primitive or an equivalent shared primitive composition.
3. When detail loading succeeds, the sheet shall render the returned `ItemDetail` as the source of truth for `content`, `isRead`, `isStarred`, `hatebuCount`, `hatebuFetchedAt`, `author`, and `link`.
4. If the caller provides summary data before detail loading completes, the sheet may show non-stale skeleton or summary metadata, but it shall replace it with the loaded `ItemDetail` once available.
5. If detail loading fails with a recoverable error, the sheet shall show a recoverable error state with retry affordance using #27 shared error primitive.
6. When retry is activated, the ViewModel shall retry the detail fetch for the same item id without requiring the parent screen to reopen the sheet.
7. The ViewModel shall not construct HTTP requests, read Keychain directly, or depend on real `URLSession`; repository and app auth state provide the boundary.

### Requirement 3: Source, title, and metadata display

**Objective:** As an 記事詳細閲覧者, I want source、title、metadata を sheet 上部で確認できる, so that 記事の出所と状態を開いた直後に判断できる

#### Acceptance Criteria

1. When detail data is available, the sheet shall display feed title and favicon using the existing favicon component or Article metadata source row.
2. When `feedFaviconURL` is a `data:` URL or nil, the sheet shall not pass it to `AsyncImage(url:)`; it shall rely on the #25 favicon / letter avatar behavior.
3. When title is long, the title shall wrap within the sheet content area without overlapping source row, metadata controls, or footer actions.
4. When published date is available, the sheet shall display formatted date text derived from the RFC3339 `String` at the display layer.
5. When `isDateEstimated` is true, the metadata display shall indicate the estimated date state in the same spirit as the article card metadata.
6. When author is available, the sheet should display author as secondary metadata without crowding the source row.
7. When hatebu metadata is available, the sheet shall display hatebu count using the shared metadata control behavior that distinguishes unavailable from zero.
8. When star state is available, the sheet shall display star state using the shared star control behavior and accessible labels.

### Requirement 4: Content preview behavior

**Objective:** As an 記事詳細閲覧者, I want 長い本文 preview を sheet 内で読める, so that medium / large detent でも layout が破綻しない

#### Acceptance Criteria

1. When content is long, preview shall be scrollable or expandable without layout overlap.
2. When `content` is present, the sheet shall render a readable preview from the HTML string using `AttributedString` conversion, simplified rendering, or a safe plain-text fallback.
3. When HTML rendering cannot preserve unsupported tags, the sheet shall fail gracefully to readable text rather than showing raw, disruptive markup as the primary experience.
4. When `content` is nil or empty, the sheet shall show a concise empty preview state using `summary` when available, or a neutral message when no preview text exists.
5. When the content area scrolls, the fixed footer action area shall remain visually separated and shall not cover the final content without sufficient bottom inset.
6. When the sheet is in medium detent, content preview may be visually truncated or collapsed, but it shall provide a clear way to continue reading by scrolling, expanding, or dragging to large detent.
7. When the sheet is in large detent, the content area shall allow reading longer content without title / metadata / footer overlap.

### Requirement 5: Read marking on open

**Objective:** As a user, I want 開いた記事が既読として扱われる, so that 詳細閲覧が既読状態へ反映される

#### Acceptance Criteria

1. When sheet opens, read marking shall be requested.
2. When read marking is requested, the ViewModel shall call `ItemRepository.updateItemState` with a partial body equivalent to `is_read: true` and without forcing `is_starred`.
3. When the opened detail is already read, the ViewModel may skip duplicate read mutation or may send an idempotent `is_read: true` request, but it shall not mark the item unread.
4. If read marking fails, the sheet shall remain usable and shall surface a non-blocking error through toast/banner or local error state rather than dismissing automatically.
5. When read marking succeeds, #35 shall update only the sheet-local state required for the current detail display.
6. The implementation shall not perform global list sync, cross-screen optimistic update, or rollback orchestration in this Issue.
7. The implementation shall not require the detail fetch to complete before requesting read marking if the item id and access token are already available, unless existing ViewModel structure makes sequencing simpler.

### Requirement 6: Detail actions

**Objective:** As an 記事詳細閲覧者, I want detail sheet から star 操作と元記事 action を見つけられる, so that 主要操作が一覧と同じ場所に揃う

#### Acceptance Criteria

1. When detail data is available, the sheet shall show a fixed footer action area containing a primary「元記事を開く」action affordance and a star affordance consistent with `design/SPEC-iOS.md` §5.4.
2. When the user activates the star affordance, the ViewModel shall call `ItemRepository.updateItemState` with a partial body equivalent to `is_starred` only, unless a combined partial update is explicitly required by current state handling.
3. When star update is in flight, the star control shall prevent ambiguous repeated updates or otherwise define deterministic behavior for repeated taps.
4. If star update succeeds, the sheet-local star state shall reflect the updated value.
5. If star update fails, the sheet shall surface a recoverable or transient error and shall not silently present the wrong final star state.
6. When the user activates「元記事を開く」, #35 shall not present SFSafariViewController because Safari opening is out of scope.
7. When Safari opening is out of scope, the primary action may call a caller-provided callback, expose a disabled / placeholder action, or surface a scoped not-yet-wired event, but it shall not implement Safari presenter logic inside `ArticleDetail`.
8. When `link` is missing or invalid despite API expectations, the open-original affordance shall be disabled or hidden without crashing.

### Requirement 7: Accessibility and visual consistency

**Objective:** As an iOS user, I want detail sheet controls to be accessible and visually consistent, so that article detail works with VoiceOver, Dynamic Type, light mode, and dark mode

#### Acceptance Criteria

1. The sheet shall provide accessible labels for dismiss, star, open-original, loading, error retry, and content preview areas where appropriate.
2. The star control shall expose selected / unselected state accessibly.
3. Icon-only controls shall not rely on color alone to communicate their purpose or state.
4. The sheet shall use `FeedmanTheme` semantic tokens and existing DesignSystem controls rather than feature-local raw color palettes.
5. The sheet shall support light and dark mode without unreadable foreground / background combinations.
6. The sheet shall preserve touch targets suitable for iOS controls.
7. The sheet shall avoid showing v1 scope-out keyword notification UI or drawer routes.

### Requirement 8: Test and verification expectations

**Objective:** As a QA / Developer, I want ArticleDetail の state transitions を小さく検証できる, so that detail UI の repository 呼び出しと error handling が後続画面に影響しない

#### Acceptance Criteria

1. When the ArticleDetail ViewModel is initialized or opened with an item id, tests shall verify it requests detail data from mock `ItemRepository`.
2. When the sheet opens, tests shall verify read marking requests `isRead == true` and `isStarred == nil`.
3. When detail loading succeeds, tests shall verify UI state contains source, title, metadata, content preview input, and current star state.
4. When detail loading fails, tests shall verify recoverable error state and retry behavior.
5. When star is toggled, tests shall verify partial star update request and sheet-local state transition on success.
6. When star update fails, tests shall verify the failure is surfaced and final sheet-local state is deterministic.
7. When content is nil, empty, or long, tests or manual verification notes shall cover fallback preview and non-overlap behavior.
8. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。macOS/Xcode 環境では `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行する。

## 非機能要件

### NFR 1: Architecture and compatibility

1. The implementation shall support iOS 16+ SwiftUI.
2. The ArticleDetail View / ViewModel shall follow MVVM + Repository and shall not directly use `URLSession`、Keychain、または request body encoding。
3. The implementation shall use Swift Concurrency (`async` / `await`) for repository calls.
4. `@MainActor` が必要な ViewModel / UI state は明示する。
5. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Scope control

1. The implementation shall keep primary edits under `Feedman/Features/ArticleDetail/` and use existing DesignSystem / Core APIs without broad refactor.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not introduce new server API contracts or depend on prototype mock JSON shapes.
4. The implementation shall not implement Safari presentation or global state sync in this Issue.

### NFR 3: Error handling and security

1. The ViewModel shall map repository errors to UI-presentable domain state without swallowing failures silently.
2. The implementation shall not commit real tokens, Secret、個人情報、または実ユーザーの記事データ。
3. Tests shall use mock repositories and dummy item ids / tokens only.
4. Auth-required failures from repository calls shall be exposed through existing app-level auth handling boundary where available, not converted into unrelated generic UI success.

## 実装境界

- `ArticleDetail` Feature は、親画面から item id、必要なら summary metadata、access token または app auth context、dismiss / open-original callback を受け取る形を優先する。
- `ItemDetail.content` は optional なので、nil / empty fallback を必ず持つ。
- 日付は API model の RFC3339 `String` を保持し、表示層で整形する。`Date` 自動 decode には頼らない。
- Star と hatebu の表示は #26 の shared metadata controls を再利用できる範囲で利用する。
- Sheet chrome / footer は #27 の `FeedmanSheetShell` を優先するが、ArticleDetail 固有の footer action layout が必要な場合も #27 の token / primitive 方針に従う。
- Read marking と star mutation は #34 の `ItemRepository.updateItemState` に委譲する。

## 確認事項

- #27 / #34 は `develop` merge 済み・`main` 未到達のため、#35 実装 branch がそれらの実装を含んでいるか実装開始時に確認する必要がある。
- `FeedmanSheetShell` の既存 action bar は単一 primary action 前提である。#35 の footer は primary「元記事を開く」+ star の 2 action を求めるため、既存 shell をそのまま使うか、ArticleDetail 内で footer を構成するかを実装時に判断する。
- 「元記事を開く」は視覚上必要だが Safari opening はスコープ外である。実装時は caller-provided callback に留めるのか、disabled 表示にするのか、後続 Safari Issue へ接続する placeholder event にするのかを確認する。
- HTML `content` の renderer は仕様上 `AttributedString` または簡易レンダでよい。採用方式と sanitizing / plain-text fallback の境界は実装時に既存 helper の有無を確認して決める。
- Read marking failure を toast、banner、または sheet-local non-blocking message のどれで見せるかは、#27 primitive の実装状態と親画面の toast center wiring に合わせて決める。
