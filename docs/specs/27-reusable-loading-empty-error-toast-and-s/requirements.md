# Issue #27 Reusable loading empty error toast and sheet primitives 要件定義

## 背景

Issue #27 は Parent: #4 の子 Issue として、後続の feature screen が共通して使う loading、empty、error、toast/banner、sheet shell の SwiftUI primitive を用意する。
`design/SPEC-iOS.md` では、各一覧に空状態 / エラー / ローディングを用意し、プロトタイプの `FMEmpty` を参照できること、記事詳細・登録・設定などは `.sheet` + `.presentationDetents([.medium, .large])` を使うことが示されている。
`design/mobile/fm-screens.jsx` と `design/mobile/fm-sheets.jsx` には `FMEmpty`、scrim、bottom sheet shell、toast の視覚例があるが、React Web の mock 実装であり、SwiftUI の API 形や画面別 business logic の正本として扱わない。

Issue コメントでは、依存 `Depends on: #24` が PR #64 として `develop` へ merge 済みであり、`codex-blocked` が除去され、`codex-auto-dev` が付与されたことが人間により確認されている。追加の仕様決定はなく、Path Overlap Checker の edit path は `Feedman/DesignSystem/` と `Feedman/Features/` とされている。

## スコープ

- `Feedman/DesignSystem` に共有 UI primitive を追加する。
- loading state、empty state、recoverable error state、toast/banner、sheet shell を SwiftUI view または view modifier として提供する。
- primitive は Issue #24 の `FeedmanTheme` token を利用し、画面側が raw color literal を重複定義しないようにする。
- primitive は feature screen から再利用できる薄い部品に留め、表示する文言、アイコン、retry action、dismiss action などは呼び出し側から渡せるようにする。
- 必要な場合のみ、既存 feature placeholder から preview または最小の利用例を追加して再利用 API を確認する。

## スコープ外

- Feature-specific business logic。
- Timeline、feed detail、starred、search、feed registration、settings、account など個別 feature の本実装。
- API request、Repository、ViewModel の loading/error state machine の実装。
- endpoint ごとの error code/action 解釈、cooldown 表示、auth 失効時の logout 制御。
- `SFSafariViewController`、read/star 更新、feed resume、registration submit などの user action 実装。
- キーワード通知 UI とその drawer / sheet 導線。
- 独自の bottom sheet gesture engine の全面実装。SwiftUI `.sheet` と `.presentationDetents` で表現できる範囲を優先する。

## 要件

### Requirement 1: Loading primitive

**Objective:** As a feature screen 実装者, I want 共通の loading 表示を使える, so that 各画面が同じ見た目とアクセシビリティで初回読み込みや追加読み込みを表現できる

#### Acceptance Criteria

1. When a screen is waiting for initial content, the DesignSystem shall provide a loading primitive that can show an activity indicator and optional short message.
2. When a paginated list is loading more items, the DesignSystem shall provide a compact loading row suitable for the bottom of a list.
3. When loading text is omitted, the loading primitive shall still expose an accessible loading label.
4. While loading is shown, the primitive shall use stable dimensions so that spinner, label, and surrounding list content do not overlap or cause avoidable layout jump.
5. The loading primitive shall use `FeedmanTheme` semantic tokens for foreground, muted foreground, surface, and border roles instead of hard-coded feature-local colors.

### Requirement 2: Empty state primitive

**Objective:** As a feature screen 実装者, I want 共通の empty state を icon/title/subtitle で表示できる, so that list が空のときに prototype と整合した案内を画面ごとに実装できる

#### Acceptance Criteria

1. When a screen has no items, the empty state shall show an icon, title, and optional subtitle without overlap.
2. When subtitle is long or Dynamic Type is larger, the empty state shall wrap text within its container and keep the icon/title/subtitle readable.
3. When the caller provides an optional primary action, the empty state shall render a clear action affordance without requiring feature screens to build their own layout.
4. If no primary action is provided, the empty state shall not reserve an interactive control area.
5. The empty state shall support SF Symbols or an equivalent SwiftUI icon source without depending on prototype-only icon names.
6. The empty state shall use `FeedmanTheme` muted surface, muted foreground, foreground, and accent tokens.

### Requirement 3: Recoverable error primitive

**Objective:** As a ViewModel / feature screen 実装者, I want 回復可能な error 表示と retry 導線を共通化できる, so that API 失敗時の画面ごとの表現差を抑えられる

#### Acceptance Criteria

1. When a recoverable error occurs, the error view shall expose retry affordance.
2. When an error message is provided, the error view shall show title and message in a readable hierarchy.
3. If retry is not applicable, the error view shall support a non-retry presentation that does not show a disabled or misleading retry button.
4. When the error represents a destructive or warning condition, the error view shall be able to use the `danger` token for icon or emphasis.
5. The error primitive shall not inspect `FeedmanAPIError` or endpoint-specific error codes directly; mapping typed errors to title/message/action remains ViewModel responsibility.
6. The error primitive shall provide accessible labels for the error content and retry control.

### Requirement 4: Toast and banner primitive

**Objective:** As a feature screen 実装者, I want 一時的な feedback を共通の toast/banner で表示できる, so that 保存完了、登録完了、外部ブラウザ起動などの短い通知を予測可能に扱える

#### Acceptance Criteria

1. When transient feedback is needed, the toast/banner shall present and dismiss predictably.
2. When a toast is shown, the primitive shall support message text and optional status icon without blocking normal screen interaction.
3. When a banner is shown for a feed stopped/error state or similar inline status, the primitive shall support message text and optional action affordance.
4. If multiple toast messages are requested in sequence, the presentation API shall define deterministic replacement or queue behavior so callers do not need ad hoc timers.
5. When toast/banner text is long, the primitive shall avoid truncating critical information in a way that overlaps adjacent controls.
6. The toast/banner primitive shall use theme tokens and shall avoid feature-local raw black/white overlays except through DesignSystem-defined semantic styling.
7. The toast/banner primitive shall not implement endpoint-specific retry, resume, registration, or logout behavior.

### Requirement 5: Sheet shell primitive

**Objective:** As a feature screen 実装者, I want bottom sheet の shell を共通化できる, so that article detail、feed registration、settings、account などの sheet が同じ chrome、detent、dismiss 表現を持てる

#### Acceptance Criteria

1. When a feature presents a sheet, the sheet shell shall provide a reusable header area with title, optional subtitle, and dismiss affordance.
2. When medium and large presentation are appropriate, the sheet shell shall support `.presentationDetents([.medium, .large])` or an equivalent iOS 16+ SwiftUI detent configuration.
3. When the sheet content needs scrolling, the sheet shell shall allow content to scroll without hiding the dismiss affordance or primary action area.
4. When a primary bottom action is supplied, the sheet shell shall keep that action visually separated from scrollable content using theme border/surface tokens.
5. When no primary action is supplied, the sheet shell shall not reserve an empty action bar.
6. The sheet shell shall provide accessible labels for the dismiss control and sheet title.
7. The sheet shell shall rely on native SwiftUI sheet behavior where possible and shall not recreate prototype-only drag physics unless a later Issue explicitly scopes it.

### Requirement 6: Integration boundary and previews/tests

**Objective:** As a QA/Developer, I want shared primitive の契約が小さく検証される, so that 後続 feature が同じ部品を安心して採用できる

#### Acceptance Criteria

1. When the shared primitives are added, the implementation shall keep reusable components under `Feedman/DesignSystem` unless minimal preview or project-file wiring is required.
2. When SwiftUI previews are available, the primitives shall include representative loading, empty, error, toast/banner, and sheet shell states in light and dark mode.
3. When unit-level tests are practical without UI snapshot infrastructure, the test suite shall verify deterministic state helpers such as toast replacement/queue behavior.
4. When UI-only layout details cannot be meaningfully unit tested, the implementation shall document manual verification points in impl notes instead of adding brittle tests.
5. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The shared primitives shall support iOS 16+ SwiftUI.
2. The shared primitives shall be usable from MVVM feature screens without directly depending on `URLSession`、Keychain、Repository 実装、または APIClient。
3. The shared primitives shall use Swift type names, identifiers, and file names in English.
4. The shared primitives shall preserve Dynamic Type readability and avoid fixed text layouts that clip normal Japanese UI strings.

### NFR 2: Accessibility

1. The shared primitives shall provide accessible labels for loading state, empty state icons where meaningful, retry buttons, dismiss buttons, and toast/banner status.
2. The shared primitives shall not rely on color alone to communicate error or success state.
3. The shared primitives shall maintain touch targets suitable for iOS controls when actions are present.

### NFR 3: Scope control

1. The implementation shall remain within Issue #27 の shared UI primitive responsibility.
2. The implementation shall not rewrite `docs/specs/*` の確定済み仕様、`design/SPEC-iOS.md`、`design/SERVER.md`、または prototype files。
3. The implementation shall not introduce feature-specific API contracts or mock data shapes as shared UI requirements.
4. The implementation shall not show v1 scope-out keyword notification UI.

## 実装境界

- 対象は `Feedman/DesignSystem` の SwiftUI primitive と、必要最小限の Xcode project wiring に限定する。
- Feature 側は、shared primitive が ViewModel から渡された state/message/action を表示できることを確認する程度に留める。
- Loading、empty、error、toast/banner、sheet shell はそれぞれ独立して使える API にし、すべてを単一の巨大な state container に結合しない。
- API layer の typed error decoding は Issue #15 / #16 の責務であり、本 Issue では UI 表示へ渡された文字列と action を表示する境界だけを扱う。

## 確認事項

- Toast の replacement / queue の最終仕様は実装時に一つへ固定する。呼び出し側が複数 timer を持たないことを優先する。
- Banner を toast と同じ型で扱うか、inline status view として分けるかは、既存 DesignSystem の分割に合わせて決める。
- Sheet shell の具体的な型名と action bar API は、記事詳細、登録、設定、アカウント sheet の後続 Issue が自然に利用できる形を優先する。
- Visual parity は `design/Feedman iPhone.html` と `design/mobile/*.jsx` を参考にするが、SwiftUI native control と iOS 16+ の制約を優先する。
