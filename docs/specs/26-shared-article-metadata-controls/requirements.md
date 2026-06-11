# Issue #26 Shared article metadata controls 要件定義

## 背景

Epic #4 の記事一覧 UI を後続 feature で再利用できるようにするため、記事カード内で共通利用する article metadata controls を定義する。
Issue #26 のゴールは、Reusable star、hatebu count、source row、open-link controls を article cards で利用可能にすることである。

Issue 本文の依存 `Depends on: #24, #25` は、Issue コメントで人間により PR #64 / PR #68 として develop merge 済みであることが確認されている。そのため、本 Issue は #24 の Feedman theme tokens と #25 の favicon data URL / letter avatar view を利用できる前提で進める。

`design/SPEC-iOS.md` では、新着横断タイムラインのカードに「フィード名 + favicon、相対日時、タイトル、概要、はてブ数、スター、外部リンクアイコン」を表示し、スターは一覧/詳細/スター一覧で整合し、外部リンクは SFSafariViewController で `link` を開くと定義されている。一方、本 Issue のスコープ外として Network state mutations and full article detail sheet が明示されているため、共有 control は表示とユーザー操作イベントの発火までを責務とし、`PUT /api/items/{id}/state`、楽観的更新、SFSafariViewController の実起動、記事詳細 sheet 本体は扱わない。

## 参照仕様

- `design/SPEC-iOS.md` §4.2, §4.3, §4.4, §5.1, §5.2, §5.3, §5.4, §6, §10
- `design/SERVER.md` §1 の Bearer 認証前提。今回の UI component に直接追加するサーバー API 契約はない。
- `design/Feedman iPhone.html` の actions `toggleStar` / `openLink` と API メモ。
- `design/mobile/fm-ui.jsx` の `FMStar`、`FMOpenLink`、`FMHatebu`、`FMTimelineCard`、`FMArticleCard`。
- `design/mobile/fm-sheets.jsx` の article detail 内 source row / hatebu / star / open original の視覚参考。ただし full article detail sheet は本 Issue の実装対象外。

## スコープ

- `Feedman/DesignSystem` または共有 UI 層に、記事カードで再利用できる star control、hatebu count control、source row、open-link control を追加する。
- #24 の theme tokens を利用し、star、accent、muted foreground、border、surface などを raw color literal で重複定義しない。
- #25 の favicon component を source row で利用し、`feed_favicon_url` / `favicon_url` が `data:` URL または `nil` でも layout が揺れないようにする。
- 横断タイムライン、スター一覧、検索結果、フィード別記事一覧など、article card 側から同じ control を組み合わせられる API にする。
- control の tap / accessibility / disabled state / unavailable state / truncation を定義する。

## スコープ外

- `PUT /api/items/{id}/state` によるスター・既読の network mutation。
- スターや既読の楽観的更新、失敗時 rollback、Repository / ViewModel の状態同期。
- SFSafariViewController の presenter 実装、外部リンクを開いた後の既読化。
- full article detail sheet / partial detail sheet 本体の実装や内容表示。
- 新規 API、API model 契約変更、サーバー変更。
- OGP thumbnail、keyword push notification UI、feed-scoped search UI。
- #24 / #25 の確定済み仕様の変更。

## 要件

### Requirement 1: Reusable star control

**Objective:** As a 記事カード実装者, I want 共通 star control を使える, so that 横断タイムライン、フィード別一覧、スター一覧、検索結果でスター表示と操作の見た目が揃う

#### Acceptance Criteria

1. When an item is starred, the star control shall render a filled star using the DesignSystem `star` color.
2. When an item is not starred, the star control shall render an unfilled star using muted foreground color.
3. When an item is starred, the star control shall expose an accessible label equivalent to「スターを解除」and an active pressed/selected state.
4. When an item is not starred, the star control shall expose an accessible label equivalent to「スターを付ける」and an inactive pressed/selected state.
5. When the user activates the star control, the star control shall call a caller-provided action without directly performing network mutation.
6. When the star control is placed inside a tappable article card, the star control shall avoid also triggering the card open action.
7. When the star control is disabled by the caller, the star control shall not call the action and shall communicate the disabled state accessibly.
8. When used in compact, standard, or timeline card layouts, the star control shall keep a stable touch target and shall not resize surrounding rows when the state changes.

### Requirement 2: Hatebu count control

**Objective:** As a 記事カード実装者, I want はてブ数の共通表示を使える, so that count がある記事と未取得の記事を同じ rules で表示できる

#### Acceptance Criteria

1. When hatebu count and fetched metadata are available, the hatebu count control shall render the numeric count with the feed/article metadata row.
2. When hatebu count is unavailable, the hatebu count control shall render a neutral unavailable state such as「-」or equivalent placeholder.
3. When hatebu count is unavailable, the hatebu count control shall use muted styling and shall not imply a count of zero.
4. When hatebu count is 100 or greater, the hatebu count control should use accent styling consistent with the prototype hot state.
5. When hatebu count is below 100, the hatebu count control shall use muted styling.
6. When rendered in compact article cards, the hatebu count control shall support a compact visual size.
7. When rendered in standard or timeline cards, the hatebu count control shall align with other metadata controls without changing row height between available and unavailable states.
8. When source data type does not include `hatebu_fetched_at`, the caller shall be able to explicitly pass unavailable state instead of forcing a bogus fetched timestamp.

### Requirement 3: Source row

**Objective:** As a cross-feed article card user, I want source metadata を一貫して確認できる, so that 複数フィードが混在する画面でも記事の出所が分かる

#### Acceptance Criteria

1. When source metadata is shown, the source row shall display favicon and feed title using the #25 favicon component.
2. When source metadata includes a long feed title, the source row shall truncate the title with a single-line ellipsis without layout shift.
3. When favicon data is unavailable or invalid, the source row shall preserve the same favicon dimensions by relying on the #25 letter avatar fallback.
4. When source metadata is absent, the source row shall allow the caller to hide the row without leaving unintended blank vertical space.
5. When used in cross-feed timeline, starred list, or global search result cards, the source row should be available because multiple feeds can appear together.
6. When used in a feed-scoped article list, the source row may be hidden by the caller to avoid repeating the current feed title.
7. When relative date is displayed beside source metadata, the source row shall keep date text from overlapping the feed title by giving the title a flexible truncation area.
8. When Dynamic Type or narrow width reduces available space, the source row shall preserve favicon, avoid text overlap, and truncate nonessential text first.

### Requirement 4: Open-link control for article cards

**Objective:** As a 記事カード利用者, I want 元記事を開く control をカード上で押せる, so that 詳細 sheet を経由せずに外部記事へ移動できる

#### Acceptance Criteria

1. When an article has an openable link, the open-link control shall render an external-link icon with accessible label equivalent to「元記事をブラウザで開く」.
2. When the user activates the open-link control, the control shall call a caller-provided action with the article identity or link information.
3. When the user activates the open-link control, the control shall not directly present SFSafariViewController and shall not directly mark the article as read.
4. When the open-link control is placed inside a tappable article card, the open-link control shall avoid also triggering the card open action.
5. When an article link is missing or not openable, the open-link control shall support a disabled or hidden state chosen by the caller.
6. When disabled, the open-link control shall communicate the unavailable state accessibly and shall not call the action.
7. When used in compact, standard, or timeline card layouts, the open-link control shall keep stable dimensions so neighboring metadata does not jump.

### Requirement 5: Article card composition support

**Objective:** As a Feature 実装者, I want article card metadata controls を組み合わせられる, so that 各一覧画面が同じ部品で仕様どおりの card を構成できる

#### Acceptance Criteria

1. When building the adopted cross-feed timeline card, the implementation shall be able to compose source row, relative date, title, summary, hatebu count, star control, and open-link control.
2. When building the adopted feed-specific standard article card, the implementation shall be able to compose title, optional summary, relative date, hatebu count, star control, and open-link control.
3. When building starred list or search result cards, the implementation shall be able to show source row when the caller passes source metadata.
4. When an article is read, the surrounding article card may lower opacity according to `design/SPEC-iOS.md`, but the shared metadata controls shall not own read-state mutation.
5. When card layout changes between compact, standard, and timeline variants, shared controls shall expose size/configuration options instead of requiring duplicated implementations.
6. When a control action is wired by Feature code, the shared controls shall be testable with mock callbacks without real network, Keychain, or Safari dependencies.

## 非機能要件

### NFR 1: DesignSystem consistency

1. The controls shall use #24 theme tokens for colors and shall not duplicate raw palette decisions in feature screens.
2. The source row shall use #25 favicon component and shall not pass `data:` URLs to `AsyncImage(url:)`.
3. The controls shall be usable from SwiftUI on iOS 16+.
4. The controls shall keep stable dimensions in SwiftUI lists to avoid row jitter during state changes.

### NFR 2: Accessibility

1. The star and open-link controls shall provide explicit accessibility labels.
2. The star control shall expose state through an accessibility value or trait suitable for toggle-like behavior.
3. The hatebu unavailable state shall not be announced as zero bookmarks unless the caller explicitly passes count zero.
4. Icon-only controls shall remain understandable to VoiceOver users without relying on surrounding visual text.

### NFR 3: Scope control

1. The implementation shall keep network mutations, optimistic update, and Safari presentation in caller-provided actions outside the shared controls.
2. The implementation shall remain within `Feedman/DesignSystem/` and `Feedman/Features/` except for minimal tests or project-file wiring required by the Xcode project.
3. The implementation shall not modify `docs/specs/*` from an implementation PR unless the design PR for this Issue explicitly changes the requirements.

## テスト観点

- When a starred and unstarred state is rendered, the star control shall expose distinct visual and accessibility states.
- When the star control callback is invoked in a card context, the test shall verify only the star action is called and the card open action is not called.
- When hatebu metadata is unavailable, the hatebu count control shall render the unavailable placeholder and shall not render `0`.
- When hatebu count is 100 or greater, the hatebu count control should render the hot/accent state.
- When source title is long, a snapshot or view-level test should verify the source row truncates without changing favicon dimensions.
- When open-link control is activated in a card context, the test shall verify only the open-link action is called.
- When link is unavailable and the control is disabled, the test shall verify no action is called.

## 実装境界

- Star control は `isStarred` と `onToggle` 相当の入力を受ける UI component として定義し、API request 型や Repository へ依存しない。
- Hatebu count control は `count` と「取得済み/未取得」を表す入力を受け、未取得を zero と区別する。
- Source row は feed title、favicon source、補助テキストまたは date 表示を受け、表示/非表示は呼び出し側が決める。
- Open-link control は link または article identifier と action を受けるが、実際の Safari presentation は Feature/ViewModel 側が担う。
- Article detail sheet での再利用は将来可能な API にしてよいが、本 Issue の完了条件に detail sheet 組み込みを含めない。

## 確認事項

- `ItemSummary` の hatebu 未取得判定に使う正式フィールドが `hatebu_fetched_at` でよいか、また `hatebu_count` の nullability がどう定義されるかは `design/SPEC-iOS.md` に詳細型が再掲されていないため実装前に確認する。
- `ItemSearchHit` は `hatebu_fetched_at` を含まないと仕様に明記されているため、検索結果カードで hatebu count を非表示にするのか、常に unavailable として表示するのかを確認する。
- フィード別記事一覧で source row を常に非表示にするか、将来の再利用のため caller option として残すかを確認する。
- `link` が API 上で必須か nullable か、欠損時に open-link control を hidden と disabled のどちらにするかを確認する。
