# Issue #28 Route state and custom drawer shell 要件定義

## 背景

Issue #28 は Parent: #5 の子 Issue として、Feedman iOS の app shell に明示的な route state とカスタム左ドロワー container を導入する。
`design/SPEC-iOS.md` では v1 の採用ナビゲーションを左ドロワー + 記事ビューに固定しており、iOS 標準 component ではなく、メインを右へオフセットし、scrim とドラッグ / スワイプで開閉できるカスタムサイドメニューとして実装することが示されている。
`design/mobile/fm-screens.jsx` と `design/Feedman iPhone.html` には header、scrim、drawer、drawer 内 navigation の視覚例があるが、React Web の prototype であり、SwiftUI の API 形、mock data、キーワード通知 UI を API 契約や v1 実装範囲として扱わない。

Issue コメントでは、依存 `Depends on: #24, #27` が PR #64 / PR #69 として `develop` へ merge 済みであり、`codex-blocked` が除去され、`codex-auto-dev` が付与されたことが人間により確認されている。Path Overlap Checker の edit path は `Feedman/` とされている。

## スコープ

- `Feedman/Features/AppShell` を中心に、app shell が保持する明示的な route state を定義する。
- route state は少なくとも「すべての新着」「お気に入り」「フィード別一覧」「検索」「アカウントへの導線」を表現できるようにする。
- 左ドロワーの開閉 state を route state とは独立して保持し、閉じる操作で現在 route が変わらないようにする。
- ハンバーガーメニュー、scrim、ドロワー本体、ドロワー項目選択の最小 interaction を SwiftUI で実装できる要件にする。
- ドロワー内のフィード一覧は real subscriptions API ではなく、既存 preview/mock repository または最小 placeholder data で route 遷移を確認できる範囲に留める。
- Issue #24 の `FeedmanTheme` と Issue #27 の shared primitives を利用できる場合は利用し、raw color や重複 UI primitive を増やさない。

## スコープ外

- Real subscriptions API integration。
- Timeline、feed detail、starred、search、feed registration、settings、account など feature-specific content の本実装。
- 記事詳細 sheet、既読、スター、SFSafariViewController、feed settings、feed registration、logout / delete account の business logic。
- API request、Repository、ViewModel、pagination、auth refresh、Keychain など data layer の追加実装。
- キーワードプッシュ通知 UI と drawer 導線。
- 下タブ navigation (`TabView`) の実装または復活。
- prototype と同等の Web 由来 animation / gesture physics の完全再現。

## 要件

### Requirement 1: Explicit route state

**Objective:** As a SwiftUI app shell 実装者, I want app shell の現在位置を型安全な route state として保持できる, so that drawer、toolbar、screen container が同じ navigation 状態を参照できる

#### Acceptance Criteria

1. When the app shell is initialized, the current route shall default to the cross-feed timeline route.
2. When the route represents the cross-feed timeline, the shell shall show the title `すべての新着`.
3. When the route represents starred items, the shell shall show the title `お気に入り`.
4. When the route represents search, the shell shall show the title `検索` or present the search route in a way that keeps route state explicit.
5. When the route represents a feed-specific list, the route shall carry a stable feed identifier separately from the display title.
6. If a feed-specific route is selected for a feed that is not present in the current mock / preview feed list, the shell shall render a safe placeholder or fallback instead of crashing.
7. When route state changes, the selected drawer item and toolbar title shall update from the same source of truth.

### Requirement 2: Drawer open and close behavior

**Objective:** As a Feedman user, I want the menu button to reveal a left drawer over the current screen, so that I can move between primary app areas without losing current context accidentally

#### Acceptance Criteria

1. When the user taps the menu button, the drawer shall open from the left with a scrim over the current screen.
2. When the drawer is open, the current content shall not receive accidental taps through the scrim.
3. When the user taps the scrim, the drawer shall close and the current route shall remain unchanged.
4. When the drawer is dismissed by a close gesture or equivalent dismiss action, the drawer shall close and the current route shall remain unchanged.
5. When the drawer opens or closes, the shell shall keep the route state and drawer-open state independent so that animation state does not become the navigation source of truth.
6. While the drawer is closed, the scrim shall not intercept touches or VoiceOver focus.

### Requirement 3: Drawer route selection

**Objective:** As a Feedman user, I want drawer items to close the drawer and navigate to the selected route, so that route changes are deliberate and visible

#### Acceptance Criteria

1. When the user selects `すべての新着` in the drawer, the drawer shall close and the route shall update to the cross-feed timeline route.
2. When the user selects `お気に入り` in the drawer, the drawer shall close and the route shall update to the starred route.
3. When the user selects a feed item in the drawer, the drawer shall close and the route shall update to that feed's item-list route.
4. When the user selects `アカウント` in the drawer, the drawer shall close and the shell shall move to the account route or present the account surface through an explicit app-shell state.
5. If the selected drawer item already matches the current route, the drawer shall still close without resetting feature-local state unnecessarily.
6. When route selection closes the drawer, the close operation shall not trigger an additional unrelated route transition.

### Requirement 4: Drawer content boundary

**Objective:** As a Product Manager, I want the drawer shell to expose only v1 in-scope navigation, so that later features do not leak into the v1 app shell

#### Acceptance Criteria

1. When the app runs in v1, the drawer shall not expose keyword notification settings.
2. When the drawer shows feed entries, the entries shall be treated as navigation placeholders or mock / preview subscriptions for this Issue.
3. When the drawer shows unread counts or feed status indicators, they shall be visual shell data only and shall not require real subscriptions API integration in this Issue.
4. When the user taps a feed settings affordance, this Issue shall not require implementing the settings sheet behavior; the implementation may omit it or leave a non-functional placeholder outside the primary route selection path.
5. If prototype content conflicts with `design/SPEC-iOS.md` or `design/SERVER.md`, the implementation shall follow the canonical specs and keep prototype-only next-phase UI hidden.

### Requirement 5: Toolbar integration

**Objective:** As a Feedman user, I want the app shell toolbar to stay consistent across routes, so that global navigation controls remain predictable

#### Acceptance Criteria

1. When a primary content route is visible, the toolbar shall provide a menu button with an accessible label `メニュー`.
2. When the menu button is tapped while the drawer is closed, the drawer shall open.
3. When the menu button is tapped while the drawer is open, the implementation may close the drawer or keep the drawer open, but the behavior shall be deterministic.
4. When the search control is present, tapping it shall update explicit route state to search or present a search surface through explicit app-shell state.
5. When the theme toggle is present in the shell or drawer, it shall not be required to implement persistent theme settings in this Issue.
6. When the route title is long, the toolbar title shall truncate or wrap according to iOS conventions without overlapping menu or trailing controls.

### Requirement 6: Accessibility and layout

**Objective:** As a VoiceOver or Dynamic Type user, I want drawer navigation to be reachable and understandable, so that app shell navigation is usable without relying on visual-only cues

#### Acceptance Criteria

1. When VoiceOver is enabled, drawer controls shall have meaningful labels.
2. When the drawer is open, VoiceOver focus shall be able to reach drawer controls and dismiss controls without focusing obscured content first.
3. When the drawer is closed, hidden drawer controls shall not remain the primary accessibility focus target.
4. When a drawer item is the current route, its selected state shall be conveyed visually and accessibly where SwiftUI supports it.
5. When Dynamic Type is larger, drawer item labels shall remain readable and shall not overlap unread counts, status icons, or settings affordances.
6. When the device uses light or dark appearance, the drawer, scrim, selected state, and borders shall use `FeedmanTheme` semantic tokens or existing DesignSystem styles.

### Requirement 7: Implementation boundary and verification

**Objective:** As a Developer / QA, I want this shell change to be small and verifiable, so that later feature Issues can build on the route contract

#### Acceptance Criteria

1. When the implementation is added, it shall keep app shell code under `Feedman/Features/AppShell` unless shared DesignSystem reuse or project-file wiring is necessary.
2. When tests are practical without UI automation, the test suite shall verify route state transitions for menu selection and dismiss behavior at the smallest useful unit.
3. When UI gesture or SwiftUI layout behavior cannot be meaningfully unit tested, the implementation shall document manual verification points in impl notes.
4. When Xcode test is available, the implementation shall be validated with `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
5. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The app shell shall support iOS 16+ SwiftUI.
2. The route state and drawer shell shall be usable from MVVM feature screens without directly depending on `URLSession`、Keychain、APIClient、または real Repository 実装。
3. Swift の型名、識別子、ファイル名は English にする。
4. The app shell shall avoid introducing global singleton navigation state unless it is already an established project pattern.

### NFR 2: Scope control

1. The implementation shall remain within Issue #28 の route state and custom drawer shell responsibility.
2. The implementation shall not rewrite `docs/specs/*` の確定済み仕様、`design/SPEC-iOS.md`、`design/SERVER.md`、または prototype files。
3. The implementation shall not introduce API contracts or mock JSON shapes as canonical requirements.
4. The implementation shall not show v1 scope-out keyword notification UI.

### NFR 3: Visual consistency

1. The drawer shall visually align with the prototype direction: left-side panel, app header, primary route entries, feed section, footer actions, scrim, and selected route affordance.
2. The implementation shall prefer existing `FeedmanTheme` and shared primitives over feature-local raw styling.
3. The drawer width and animation shall be stable across supported iPhone sizes and shall not cause toolbar, list rows, or drawer labels to overlap.

## 実装境界

- 対象は app shell route state、drawer-open state、toolbar menu action、drawer route selection、scrim dismiss の契約に限定する。
- `Timeline`、`Starred`、`Search`、`Feed`、`Account` の各 route は、この Issue では shell が表示先を切り替えられる最小 placeholder または既存 placeholder で足りる。
- Feed list は後続 Issue の real subscriptions API integration の入力になるため、この Issue では mock / preview data の範囲で route ID と label を扱う。
- Drawer の gesture は、tap dismiss と SwiftUI で自然に実装できる close gesture までを優先し、prototype の drag physics 完全再現は後続判断に送る。
- Account は v1 スコープ内だが、本 Issue では drawer から到達できる route / presentation state の確保に留め、ログアウト・退会処理は後続 Issue の責務とする。

## 確認事項

- 現時点で Issue #28 を実装前に追加確認すべき未決事項はない。
- アカウントを dedicated route にするか sheet presentation にするかは、既存 AppShell の構造に合わせて実装時に一つへ固定する。ただし、いずれの場合も app shell の明示 state として扱う。
- Search を route として扱うか、search surface presentation state として扱うかは、既存 AppShell の構造に合わせて実装時に一つへ固定する。ただし、toolbar 操作の結果が暗黙 state にならないことを優先する。
