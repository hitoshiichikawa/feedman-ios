# Issue #52 Accessibility and Dynamic Type pass 要件定義

## 背景

Issue #52 は Parent: #12 の子 Issue として、v1 の primary flows が VoiceOver と大きい Dynamic Type でも基本的に利用できる状態へ仕上げる。対象は、Google ログイン、認証復元後の app shell、横断タイムライン、フィード別記事一覧、記事詳細 sheet、元記事を開く導線、既読 / スター、スター一覧、横断検索、フィード登録、購読設定、アカウント、ログアウト、退会である。

`design/SPEC-iOS.md` では v1 スコープが上記 primary flows に限定され、視覚仕様では Dynamic Type 対応が推奨されている。`design/IDD-CODEX-ISSUES.md` の Issue I12 では、v1 hardening として Dynamic Type と VoiceOver の基本対応、primary navigation / star / open link / sheet controls の accessible labels が示されている。

既存 Issue では、#28 と #30 が drawer / toolbar の VoiceOver と Dynamic Type の基礎、#32 / #35 / #40 / #45 / #46 が主要画面ごとの accessibility 断片、#51 が loading / error / retry polish を扱っている。本 Issue はこれらを前提に、primary v1 flows の VoiceOver labels と larger Dynamic Type の抜け漏れを横断的に閉じる。

## Issue コメントの反映

`gh issue view 52 --comments` で確認できたコメントは以下である。

- 依存 Issue #51 は `staged-for-release` になり、依存 Issue がすべて解消済みとして `codex-blocked` が自動解除された。
- Path Overlap Checker の edit path は `Feedman/` と `FeedmanTests/` である。
- ローカル Codex CLI が impl モードで処理を開始した。

本要件は #51 の loading / error / retry 表示が存在する前提で、その表示面にも VoiceOver label と Dynamic Type 非重なりを適用する。編集想定は `Feedman/` と `FeedmanTests/` に閉じ、既存の `design/*` や確定済み `docs/specs/*` は本 Issue の実装 PR で書き換えない。

## スコープ

- Primary v1 flows の VoiceOver label / value / hint / selected state / disabled state を点検し、不足分を補う。
- Icon-only controls、primary buttons、destructive actions、sheet dismiss、retry、search clear、star toggle、open-original、drawer route、feed settings、logout、delete account など、ユーザーが操作する主要 control を対象にする。
- Article card / search result / drawer feed row / account user row など、複数の visual child から成る要素について、VoiceOver で意味が分かるまとまりと順序を整える。
- 大きい Dynamic Type で、primary controls と主要 text が重ならず、必要に応じて折り返し、scroll、truncation、固定寸法の維持を行う。
- Loading、empty、error、retry、toast、banner、confirmation alert / sheet の文言が VoiceOver と Dynamic Type でも理解できることを確認する。
- XCTest で検証可能な descriptor / view model / presentation state は単体テストを追加または更新し、SwiftUI の実レイアウト確認が必要な項目は実装メモまたは PR 報告で手動確認項目として明記する。

## スコープ外

- Full App Store accessibility audit。
- WCAG / HIG 全項目の網羅監査、外部監査レポート作成、App Store 審査用 evidence package の作成。
- Switch Control、Voice Control、AssistiveTouch、Full Keyboard Access、Reduced Motion、Increase Contrast、Differentiate Without Color、字幕 / 音声など、VoiceOver labels と larger Dynamic Type を超える包括対応。
- 新しい v1+ 機能、キーワードプッシュ通知、OPML import/export、フィード URL 変更 UI、オフライン全文 cache、Feed-scoped search UI、WebView Cookie login fallback。
- 既存 navigation / repository / API 契約の再設計。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、既存確定済み `docs/specs/*` の変更。
- Pixel-perfect な prototype 再現や全 iPhone サイズの網羅 UI snapshot suite。

## 要件

### Requirement 1: Primary controls expose meaningful VoiceOver semantics

**Objective:** As a VoiceOver user, I want primary controls の目的と状態を音声で理解できる, so that 見た目だけに頼らず v1 の主要操作を実行できる

#### Acceptance Criteria

1. When VoiceOver is enabled, Google login, menu, search, theme toggle, drawer dismiss, feed registration, account, logout, and delete account controls shall expose meaningful Japanese accessibility labels.
2. When icon-only controls are used, each control shall expose a label that describes the action rather than the icon shape.
3. When a control changes state, such as theme toggle, selected route, read state, starred state, feed filter, subscription status, or busy state, the control shall expose the state through accessibility value, selected trait, disabled state, visible text, or an equivalent SwiftUI accessibility mechanism.
4. When a primary action is disabled or busy, VoiceOver shall not imply that the action can be immediately completed.
5. When a destructive action is shown, such as logout confirmation context or delete account, VoiceOver shall make the destructive purpose understandable before the user confirms it.
6. When a retry action is shown from loading / error polish surfaces, the retry label shall identify the target operation where the surrounding context is otherwise ambiguous.
7. If an existing shared DesignSystem control already provides correct semantics, the implementation shall reuse or preserve that behavior instead of replacing it with feature-local duplicate labels.

### Requirement 2: Article and list content are understandable as VoiceOver elements

**Objective:** As a VoiceOver user, I want article rows and cards to announce source, title, time, read/star state, and available actions, so that 一覧から記事を選びやすい

#### Acceptance Criteria

1. When an article card or row is focused in Timeline, Feed list, Starred list, or Search results, it shall identify the article title and source feed where the data is available.
2. When published time is available, the focused article element or nearby metadata element shall expose a readable published-time label derived from the existing display formatting.
3. When an article is read or unread, the accessible state shall not rely only on opacity.
4. When an article is starred or unstarred, the star control shall expose the current state and the toggle action.
5. When hatebu metadata is unavailable, VoiceOver shall not announce unavailable metadata as zero bookmarks.
6. When the open-original control is focused, it shall expose a label equivalent to「元記事を開く」and shall not be confused with opening the in-app detail sheet.
7. When a search result opens detail or original article through a bridge, the result control shall expose the intended destination without requiring the user to infer it from visual layout.
8. When article card child controls are focused, activating star or open-original shall not also trigger the card body action.

### Requirement 3: Sheets, alerts, and transient feedback remain accessible

**Objective:** As a VoiceOver user, I want sheet と alert のタイトル、本文、閉じる、保存、確認、再試行が順に理解できる, so that modal flow で迷わない

#### Acceptance Criteria

1. When article detail sheet is presented, dismiss, title, content preview, star, open-original, loading, error, retry, and transient message controls shall have understandable accessibility semantics.
2. When feed registration sheet is presented, the URL field, submit action, loading state, validation error, success feedback, and cancel / dismiss action shall be accessible.
3. When subscription settings sheet is presented, feed title, status, interval picker, save, resume, unsubscribe, confirmation, error, and busy states shall be accessible.
4. When account sheet is presented, current user loading / error, user name, email, logout, delete account, destructive confirmation, failure, and in-flight states shall be accessible.
5. When a sheet is dismissed, hidden sheet controls shall not remain the primary VoiceOver focus target.
6. When a toast or banner appears, it shall expose its message without stealing all navigation capability from the current flow.
7. When multiple transient messages can occur, overlapping accessibility announcements or duplicated visible messages shall be avoided by using existing deterministic toast / banner behavior or feature-local replacement.

### Requirement 4: Drawer and route navigation stay reachable with VoiceOver

**Objective:** As a VoiceOver user, I want app shell navigation を現在 route と drawer 状態に合わせて操作できる, so that 主要画面へ確実に移動できる

#### Acceptance Criteria

1. When the drawer is opened, VoiceOver focus shall be able to reach drawer route controls, feed rows, settings affordances, footer actions, and dismiss controls in a logical order.
2. While the drawer is open, obscured main content shall not remain the primary VoiceOver focus target.
3. While the drawer is closed, hidden drawer controls shall not be focusable as primary controls.
4. When a drawer route is currently selected, its selected state shall be conveyed accessibly where SwiftUI supports it.
5. When feed rows include unread count, stopped/error status, favicon/avatar, or settings affordance, the accessible label/value shall distinguish navigation from settings.
6. When keyword notification prototype entries exist in reference material, the drawer shall not expose them in v1.

### Requirement 5: Larger Dynamic Type avoids overlap in primary flows

**Objective:** As a Dynamic Type user, I want larger text settings でも primary controls が重ならず読める, so that v1 の主要操作を拡大表示で実行できる

#### Acceptance Criteria

1. When Dynamic Type is increased, primary buttons and icon buttons shall keep tappable dimensions and shall not be covered by adjacent labels, cards, banners, or sheet footers.
2. When Dynamic Type is increased, Timeline, Feed list, Starred list, and Search result article titles / source rows / summaries / metadata controls shall wrap, truncate, or scroll without overlapping star and open-original controls.
3. When Dynamic Type is increased, article detail sheet content shall keep title, metadata, preview, footer actions, and dismiss affordance reachable without incoherent overlap.
4. When Dynamic Type is increased, feed registration, subscription settings, account, logout, and delete account flows shall preserve visible labels, form fields, primary actions, destructive actions, and error text.
5. When Dynamic Type is increased, drawer route labels, feed titles, unread counts, status indicators, settings buttons, and footer actions shall remain usable through wrapping, truncation, scrolling, or stable fixed control dimensions.
6. When Dynamic Type is increased, loading / empty / error / retry / toast / banner surfaces shall remain readable and shall not hide their action controls.
7. If text cannot fit horizontally, the UI shall prefer vertical growth, wrapping, scrolling, or iOS-conventional truncation over clipping important action text.
8. If a fixed visual asset or icon is decorative, it shall not force text into overlap at larger Dynamic Type sizes.

### Requirement 6: Typography and layout changes are conservative

**Objective:** As a Developer, I want accessibility polish が既存 design system と画面責務を壊さない, so that v1 hardening として安全に適用できる

#### Acceptance Criteria

1. When fonts are adjusted, the implementation shall prefer SwiftUI text styles or existing `FeedmanTheme` / DesignSystem conventions over new hard-coded sizes.
2. When line limits are used, they shall be intentional for dense article cards and shall not clip primary action labels or destructive confirmation text.
3. When layout needs more space for larger Dynamic Type, the implementation shall prefer existing scroll containers, `fixedSize(horizontal: false, vertical: true)`, stable control frames, and layout priority adjustments before broad screen rewrites.
4. When shared controls such as `ArticleMetadataControls`, `FeedmanFaviconView`, `FeedmanLoadingView`, `FeedmanEmptyStateView`, `FeedmanRecoverableErrorView`, `FeedmanToastView`, `FeedmanBannerView`, or `FeedmanSheetShell` are changed, the change shall preserve existing callers unless the caller change is required by this Issue.
5. When accessibility modifiers are added, they shall not hide meaningful child controls such as star, open-original, retry, cancel, or destructive confirmation.
6. When visual-only read/star/status indication exists, the implementation shall add accessible text/value semantics rather than changing API models or repository contracts.
7. The implementation shall not introduce a new app-wide accessibility framework or global state store for this pass.

### Requirement 7: Coverage across primary v1 flows

**Objective:** As a QA / Product Manager, I want 対象画面ごとの確認範囲が明確である, so that #52 が Full audit に広がらず primary flows の抜けを閉じられる

#### Acceptance Criteria

1. When the implementation is complete, Login / auth restoration shall cover login button, in-flight state, cancellation / failure message, and restoration loading.
2. When the implementation is complete, AppShell / Drawer shall cover menu, search, theme, primary route navigation, feed route navigation, feed settings, footer actions, selected state, and drawer dismiss.
3. When the implementation is complete, Timeline shall cover article card focus, star, open-original, detail selection, loading, empty, error, retry, refresh feedback, and next-page footer.
4. When the implementation is complete, Feed list shall cover filter picker, feed status banner, article row/card focus, star, open-original, manual refresh / cooldown feedback, loading, empty, error, retry, and pagination footer.
5. When the implementation is complete, Article detail shall cover sheet title, source, metadata, content preview, star, open-original, close, loading, error, retry, and transient messages.
6. When the implementation is complete, Starred list shall cover article rows/cards, unstar action, open-original, detail selection, loading, empty, error, retry, and pagination footer.
7. When the implementation is complete, Global search shall cover search field, clear button, suggestion chips, submit/search action, result rows, detail/open-original actions, loading, empty, error, and retry.
8. When the implementation is complete, Feed registration shall cover URL field, submit, loading, validation, success, failure, and dismiss.
9. When the implementation is complete, Subscription settings shall cover interval selection, save, resume, unsubscribe, confirmation, loading/busy, success, failure, and dismiss.
10. When the implementation is complete, Account / logout / deletion shall cover current-user display, loading, retry, logout, delete account, destructive confirmation, busy state, failure, and unauthenticated transition boundary.

### Requirement 8: Tests and verification

**Objective:** As a QA / Developer, I want accessibility semantics と Dynamic Type regressions を実装可能な範囲で検出できる, so that v1 hardening の変更が後続で崩れにくい

#### Acceptance Criteria

1. When accessibility labels, values, hints, or descriptors are produced by non-View helper types, tests shall verify representative Japanese strings and state changes.
2. When ViewModel presentation state determines labels or disabled / busy states, tests shall verify the state needed by the View to expose correct accessibility semantics.
3. When shared DesignSystem descriptors are changed, tests shall cover selected/unselected, unavailable, loading, error, retry, and destructive/busy states where practical.
4. When UI layout behavior cannot be reliably unit tested with XCTest, the implementer shall document manual verification points for VoiceOver and larger Dynamic Type in implementation notes or final report.
5. When macOS/Xcode environment is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
6. While Xcode build/test cannot be run, the implementer shall report the exact reason and run practical local checks such as `plutil -lint` and `git diff --check`.
7. The tests shall not depend on real network, real Keychain, real OAuth, personal account data, or App Store accessibility tooling.

## 非機能要件

### NFR 1: Architecture

1. The implementation shall follow MVVM + Repository and shall not move API, Keychain, or URLSession access into Views for accessibility reasons.
2. UI-facing async state shall remain `@MainActor` where appropriate.
3. Swift type names, identifiers, and file names shall be English.
4. User-facing labels and accessibility copy shall be Japanese unless they are fixed product names or system terms.
5. API date strings shall remain RFC3339 `String` values until formatted for display.

### NFR 2: UX and safety

1. Accessibility labels shall describe the user-visible action or state and shall not expose raw API payloads, tokens, Authorization headers, private search queries beyond the current on-screen query, or unnecessary personal data.
2. Error, warning, selected, read/unread, starred/unstarred, stopped/resumed, and destructive states shall not rely on color alone.
3. Larger Dynamic Type support shall prioritize primary task completion over preserving dense prototype layout.
4. Controls shall keep practical iOS hit targets and shall not become unreachable because of added labels, wrapping, or overlays.
5. Existing light / dark appearance behavior and `FeedmanTheme` semantics shall be preserved.

### NFR 3: Scope control

1. The implementation shall remain within Issue #52 の accessibility and Dynamic Type pass responsibility.
2. The implementation shall keep expected edit paths to `Feedman/` and `FeedmanTests/`.
3. The implementation shall not create a Full App Store accessibility audit deliverable.
4. The implementation shall not add v1 scope-out UI, especially keyword notification drawer entries.
5. If a primary flow requires broad redesign to satisfy larger Dynamic Type, the implementer shall document the gap and split a follow-up Issue instead of expanding this PR beyond a polish pass.

## 実装境界

- 共有 control の修正は `Feedman/DesignSystem/` を優先し、feature 固有の不足は各 `Feedman/Features/<FeatureName>/` に閉じる。
- App shell / drawer / toolbar の調整は `Feedman/Features/AppShell/` の既存 state と modifiers を利用する。
- Article list 系の共通 semantics は、可能な範囲で `ArticleMetadataControls`、article presentation descriptor、feature-local card descriptor など既存の境界へ集約する。
- Tests は `FeedmanTests/` に追加または更新する。SwiftUI の VoiceOver 実読み上げや Dynamic Type の実レイアウトは XCTest だけで完全検証しようとしない。
- #51 の loading / error / retry primitives と画面ごとの state を前提にし、それらの挙動や retry semantics を本 Issue で再設計しない。

## 確認事項

- larger Dynamic Type の手動確認対象カテゴリを `.accessibility3` までにするか、最大カテゴリまで必須にするかは未確定である。本要件では primary controls の非重なりと到達性を優先し、実装時に確認カテゴリを明記する。
- VoiceOver の実機 / Simulator 手動確認を PR 必須 gate にするか、実装者の環境で可能な場合の確認項目に留めるかは未確定である。
- UI test / snapshot test の導入は必須にしない。既存 XCTest で扱える descriptor / ViewModel state を優先し、必要なら follow-up Issue として分離する。
