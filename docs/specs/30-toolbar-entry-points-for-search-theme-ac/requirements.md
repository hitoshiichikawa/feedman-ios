# Issue #30 Toolbar entry points for search theme account and registration 要件定義

## 背景

Issue #30 は Parent: #5 の子 Issue として、Issue #28 で導入された app shell の route state と custom drawer shell に、v1 の主要導線である検索、テーマ切替、アカウント、フィード登録の entry point を露出する。
`design/SPEC-iOS.md` では、採用ナビゲーションを左ドロワー + 記事ビューとし、トップバーは左にハンバーガー、中央にタイトル、右に検索・テーマ切替を置くこと、ドロワー内フッタにアカウント・テーマを置くことが示されている。また、フィード登録は v1 スコープ内で `.sheet` 表示の後続 feature として定義されている。

本 Issue は destination feature の本実装ではなく、app shell から各 feature へ到達できる明示的な route / presentation state と placeholder 表示を用意する薄い縦切りである。プロトタイプ `design/Feedman iPhone.html` と `design/mobile/*.jsx` は見た目と導線の参考にするが、React Web の mock data や keyword notification UI は v1 の正本として扱わない。

Issue コメントでは、依存 `Depends on: #28` が PR #71 として `develop` へ merge 済みであり、`codex-blocked` が除去され、`codex-auto-dev` が付与されたことが人間により確認されている。#29 と `AppShell` / `pbxproj` の編集範囲が重なる可能性があるが、pbxproj ID 衝突は merge 時に解消する方針である。Path Overlap Checker の edit path は `Feedman/` と `FeedmanTests/` とされている。

## スコープ

- `Feedman/Features/AppShell` を中心に、top toolbar と drawer footer へ v1 entry point を追加または整理する。
- Top toolbar は、既存の menu / title と共存しながら検索とテーマ切替へ到達できるようにする。
- Drawer footer は、アカウント、テーマ切替、フィード登録へ到達できる footer action area として扱う。
- 検索は Issue #28 の search route または同等の明示的 app-shell state へ遷移し、検索 feature の本実装は placeholder に留める。
- テーマ切替は light / dark / system follow のうち、実装範囲に合う最小の手動上書きを UI に反映する。永続化は必須にしない。
- アカウントとフィード登録は placeholder route / sheet / DesignSystem sheet shell のいずれか、既存 AppShell に自然な presentation state で表示できるようにする。
- Issue #24 の `FeedmanTheme` と Issue #27 の shared primitives を利用できる場合は利用し、raw color や重複 UI primitive を増やさない。

## スコープ外

- 横断検索の query 入力、API 呼び出し、検索結果一覧、サジェストチップの本実装。
- フィード登録の URL 入力、検出、確認、登録 API、重複 / レート制限エラー handling の本実装。
- アカウントの `GET /auth/me` 表示、ログアウト、退会、token revoke、Keychain 更新の本実装。
- テーマ設定の永続化、ユーザー設定 API、複数 accent picker、DesignSystem token の再定義。
- Feed settings、subscription settings、keyword notification、OPML、push notification への導線追加。
- 下タブ navigation (`TabView`) の実装または復活。
- Destination feature の ViewModel、Repository、APIClient、実 network integration。

## 要件

### Requirement 1: Top toolbar entry points

**Objective:** As a Feedman user, I want top toolbar から検索とテーマ切替へすぐ到達できる, so that 現在の route に関係なく global action を予測可能に使える

#### Acceptance Criteria

1. When a primary app-shell route is visible, the top toolbar shall keep the menu button, route title, and trailing global actions visible without overlap.
2. When the user taps the search toolbar button, the app shell shall move to the search placeholder route or present an explicit search surface state.
3. When the current route is already search, tapping the search toolbar button shall keep behavior deterministic and shall not push duplicate navigation state.
4. When the user taps the theme toolbar button, the app shell shall update the active visual color scheme through explicit theme override state.
5. If the device appearance changes while no manual override is active, the app shell shall continue to follow the system color scheme.
6. If a manual theme override is active, the app shell shall apply that override consistently to toolbar, drawer, scrim, placeholder content, and shared DesignSystem surfaces.
7. When toolbar actions are shown, each action shall have a Japanese accessibility label such as `検索` and `テーマ切替`.
8. When Dynamic Type or a long route title is used, toolbar title and trailing actions shall not overlap; title truncation shall follow iOS conventions.

### Requirement 2: Drawer footer entry points

**Objective:** As a Feedman user, I want drawer footer に account、theme、feed registration の導線がまとまっている, so that primary navigation と account / setup action を混同せずに使える

#### Acceptance Criteria

1. When the drawer is open, the drawer footer shall expose an account entry point.
2. When the user taps the account entry point, the drawer shall close and the app shell shall open an account placeholder route or account placeholder sheet through explicit state.
3. When the drawer is open, the drawer footer shall expose a theme toggle or equivalent theme action.
4. When the user taps the drawer footer theme action, the active visual color scheme shall update in the same way as the toolbar theme action.
5. When the drawer is open, the drawer footer shall expose a feed registration entry point labeled for registering a feed.
6. When the user taps the feed registration entry point, the drawer shall close and the app shell shall open a feed registration placeholder sheet or placeholder presentation state.
7. When footer actions are rendered, they shall remain visually separate from primary route items and feed route items.
8. When keyword notification prototype actions exist in reference material, the drawer footer shall not expose keyword notification entry points in v1.

### Requirement 3: Placeholder destination behavior

**Objective:** As a Developer / QA, I want 未実装 feature の導線が explicit placeholder に着地する, so that entry point の wiring を destination feature 実装と独立して検証できる

#### Acceptance Criteria

1. When the search entry point is activated, the resulting placeholder shall clearly represent `検索` without requiring search API integration.
2. When the account entry point is activated, the resulting placeholder shall clearly represent `アカウント` without showing real user data, logout, revoke, or delete-account behavior.
3. When the feed registration entry point is activated, the resulting placeholder shall clearly represent `フィードを登録` without submitting network requests.
4. When a placeholder is presented as a sheet, the sheet shall provide a dismiss affordance and shall use native SwiftUI sheet behavior or existing shared sheet primitive.
5. When a placeholder is presented as a route, the route shall be part of explicit app-shell state and shall update title / selected state from the same source of truth.
6. If a placeholder action is tapped repeatedly, the app shell shall not stack duplicate sheets or create inconsistent route state.
7. When placeholders use explanatory text, the text shall state that full feature implementation is handled by later Issues without implying that real API behavior exists.

### Requirement 4: Theme override state

**Objective:** As a Feedman user, I want light / dark appearance を手動で切り替えられる, so that system appearance と違う表示を必要に応じて選べる

#### Acceptance Criteria

1. When the app starts, the default theme behavior shall follow the system color scheme unless an existing project-level setting already defines otherwise.
2. When the user toggles theme from the toolbar, the app shell shall switch between light and dark manual override or an equivalent deterministic cycle including system follow.
3. When the user toggles theme from the drawer footer, the app shell shall use the same theme override state as the toolbar action.
4. When theme state changes, all visible AppShell surfaces shall update without requiring navigation away from the current route.
5. When the drawer is open and theme state changes, the drawer shall remain usable and shall not accidentally change the current content route.
6. If theme persistence is not implemented in this Issue, the app shall still behave predictably for the current app session.
7. The implementation shall not add accent color selection or redefine the Indigo theme token set in this Issue.

### Requirement 5: Accessibility and layout

**Objective:** As a VoiceOver or Dynamic Type user, I want toolbar and drawer footer actions to be understandable and reachable, so that global entry points are usable without visual-only cues

#### Acceptance Criteria

1. When VoiceOver is enabled, toolbar and drawer footer actions shall expose meaningful Japanese labels.
2. When a footer action opens a sheet, the sheet title and dismiss control shall be accessible.
3. When the drawer is closed, hidden footer actions shall not remain the primary accessibility focus target.
4. When the drawer is open, footer actions shall be reachable after primary navigation items without requiring focus on obscured main content.
5. When Dynamic Type is larger, footer action labels shall remain readable and shall not overlap icons, badges, borders, or each other.
6. When light or dark appearance is active, toolbar icons, drawer footer actions, selected state, and placeholder surfaces shall use `FeedmanTheme` semantic tokens or existing DesignSystem styles.

### Requirement 6: Integration boundary and verification

**Objective:** As a Developer / QA, I want entry point wiring を小さく検証できる, so that destination feature 実装前でも app shell の導線品質を確認できる

#### Acceptance Criteria

1. When the implementation is added, it shall keep app shell changes under `Feedman/Features/AppShell` unless shared DesignSystem reuse, tests, or project-file wiring is necessary.
2. When state helpers are practical to test without UI automation, the test suite shall verify search route activation, account / registration presentation state, drawer closing behavior, and theme override transitions.
3. When SwiftUI layout or sheet presentation cannot be meaningfully unit tested, the implementation shall document manual verification points in impl notes.
4. When Xcode test is available, the implementation shall be validated with `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
5. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The toolbar and drawer footer entry points shall support iOS 16+ SwiftUI.
2. The app shell state shall remain usable from MVVM feature screens without directly depending on `URLSession`、Keychain、APIClient、または real Repository 実装。
3. Swift の型名、識別子、ファイル名は English にする。
4. The implementation shall avoid introducing global singleton navigation or theme state unless it is already an established project pattern.

### NFR 2: Scope control

1. The implementation shall remain within Issue #30 の toolbar / drawer footer entry point responsibility.
2. The implementation shall not rewrite `docs/specs/*` の確定済み仕様、`design/SPEC-iOS.md`、`design/SERVER.md`、または prototype files。
3. The implementation shall not introduce new API contracts, mock JSON shapes, auth behavior, or feed registration network behavior.
4. The implementation shall not show v1 scope-out keyword notification UI.
5. The implementation shall not depend on Issue #29 の未確定変更を前提にしない。

### NFR 3: Visual consistency

1. The toolbar shall visually align with the prototype direction: menu button, route title, search action, and theme action.
2. The drawer footer shall visually align with the prototype direction while also exposing feed registration as a v1 setup action.
3. The implementation shall prefer existing `FeedmanTheme` and shared primitives over feature-local raw styling.
4. Toolbar and footer hit areas shall be suitable for iOS controls and shall not shrink below practical tap targets.

## 実装境界

- 対象は top toolbar actions、drawer footer actions、theme override state、search/account/register placeholder presentation wiring に限定する。
- Search は v1 スコープ内だが、本 Issue では toolbar から到達できる route / placeholder の確保までとし、query 入力と結果表示は後続 Issue の責務とする。
- Account は v1 スコープ内だが、本 Issue では placeholder route / sheet の確保までとし、ログアウト・退会処理は後続 Issue の責務とする。
- Feed registration は v1 スコープ内だが、本 Issue では placeholder sheet / presentation state の確保までとし、URL 検出と登録 API は後続 Issue の責務とする。
- Theme は v1 スコープ内だが、本 Issue では AppShell での手動 light/dark override と UI 反映までとし、永続化や settings 連携は後続判断とする。
- Drawer footer の action 配置は既存 `AppShell` の構造に合わせて実装時に調整してよいが、primary route item と footer action の役割は分ける。

## 確認事項

- 現時点で Issue #30 を実装前に追加確認すべき未決事項はない。
- Theme toggle の cycle は、既存の AppShell / DesignSystem に合わせて `system -> dark -> light -> system` または `light <-> dark` のどちらかへ実装時に固定する。ただし、toolbar と drawer footer は同じ state を使う。
- Account と feed registration は dedicated route ではなく sheet presentation でもよい。ただし、いずれの場合も app shell の明示 state として扱い、重複 presentation を防ぐ。
