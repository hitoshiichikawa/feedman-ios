# Issue #24 Feedman theme tokens 要件定義

## 背景

Epic #4 の UI 基盤を後続 feature 実装で再利用できるようにするため、Feedman の light/dark 配色と Indigo accent を SwiftUI の DesignSystem token として定義する。
`design/SPEC-iOS.md` では、プロトタイプ `design/mobile/fm-data.jsx` の `FM_THEME` をデザイントークンの正本とし、SwiftUI では oklch 値を P3/sRGB の固定 hex/RGB 近似へ変換して扱う方針が定義されている。
Issue コメントには Path Overlap Checker の edit path と自動実行通知のみがあり、人間による追加決定事項はない。

## スコープ

- `Feedman/DesignSystem` に Feedman theme token を追加または整理する。
- light mode と dark mode の semantic color token を定義する。
- accent は仕様どおり Indigo のみを採用する。
- token は SwiftUI view から再利用できる `Color` または同等の SwiftUI 向け API として提供する。
- token 名は prototype の役割を保持しつつ、Swift API Design Guidelines に沿う英語名にする。

## スコープ外

- Full component library の実装。
- Feature screens への適用、画面単位の見た目調整、既存画面の置き換え。
- Coral、Teal、Violet など prototype tweak 用 accent の実装。
- アプリ内の accent picker、theme picker、ユーザー設定による theme 永続化。
- Geist font の同梱、Dynamic Type 全体設計、safe area helper、tap target helper の実装。
- `Feedman/DesignSystem` 外の feature、repository、network、auth、asset catalog の大規模変更。

## 機能要件

- When light mode is active, shared DesignSystem consumers shall use Feedman light colors derived from `FM_THEME(false, "indigo")`.
- When dark mode is active, shared DesignSystem consumers shall use Feedman dark colors derived from `FM_THEME(true, "indigo")`.
- When accent color is needed, the app shall use the Indigo accent defined by `design/SPEC-iOS.md` and `design/mobile/fm-data.jsx`.
- When accent foreground color is needed, the app shall provide a readable on-accent token matching prototype `accentOn`.
- When subtle accent background is needed, the app shall provide an `accentSoft`-equivalent token for selected states, info strips, and soft badges.
- When neutral surfaces are needed, the app shall provide semantic tokens equivalent to `bg`, `surface`, and `surface2`.
- When text colors are needed, the app shall provide semantic tokens equivalent to `fg` and `mutedFg`.
- When muted controls or search fields are needed, the app shall provide a semantic token equivalent to `muted`.
- When borders or drag handles are needed, the app shall provide semantic tokens equivalent to `border` and `borderStrong`.
- When starred state is shown, the app shall provide a semantic `star` token for light and dark mode.
- When destructive actions are shown, the app shall provide a semantic `danger` token for light and dark mode.
- When modal scrim or drawer overlay is shown by later components, the app shall provide a semantic `scrim` token for light and dark mode.
- When status bar style or equivalent chrome contrast is decided by later app shell code, the theme shall expose enough information to distinguish light chrome from dark chrome.
- If SwiftUI `ColorScheme` changes while the app is running, theme token resolution shall reflect the active light/dark mode without requiring feature screens to hard-code colors.
- If a token is backed by fixed RGB/hex values, the implementation shall keep the source oklch role traceable to `design/mobile/fm-data.jsx`.

## Token 候補

| 役割 | Light source | Dark source | 備考 |
|---|---|---|---|
| `accent` | `oklch(0.55 0.17 264)` | `oklch(0.68 0.15 264)` | Indigo。`design/SPEC-iOS.md` では light accent を sRGB `#4F46E5` 近傍と定義。 |
| `accentOn` | `#ffffff` | `#ffffff` | accent 上の文字・アイコン。 |
| `accentSoft` | `color-mix(in oklch, accent 12%, white)` | `color-mix(in oklch, accent 18%, transparent)` | SwiftUI では固定近似または透明度付き派生色で表現する。 |
| `background` | `oklch(0.985 0 0)` | `oklch(0.145 0 0)` | prototype の `bg`。 |
| `surface` | `oklch(1 0 0)` | `oklch(0.205 0 0)` | card/sheet/control surface。 |
| `surfaceSecondary` | `oklch(0.975 0 0)` | `oklch(0.235 0 0)` | prototype の `surface2`。 |
| `foreground` | `oklch(0.205 0 0)` | `oklch(0.985 0 0)` | primary text。 |
| `muted` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | search field / placeholder surface。 |
| `mutedForeground` | `oklch(0.556 0 0)` | `oklch(0.708 0 0)` | secondary text / inactive icon。 |
| `border` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 12%)` | separator / subtle border。 |
| `borderStrong` | `oklch(0.87 0 0)` | `oklch(1 0 0 / 20%)` | handle / stronger separator。 |
| `star` | `oklch(0.78 0.16 84)` | `oklch(0.82 0.16 84)` | starred item state。 |
| `danger` | `oklch(0.577 0.245 27)` | `oklch(0.704 0.191 22)` | destructive action。 |
| `scrim` | `rgba(0,0,0,0.32)` | `rgba(0,0,0,0.6)` | modal/drawer overlay。 |

## 非機能要件

- Theme token API は iOS 16+ の SwiftUI で利用できること。
- oklch や CSS `color-mix` を runtime dependency とせず、SwiftUI が扱える固定 `Color` 値または明確な派生計算に落とすこと。
- token は semantic name を優先し、feature view が raw RGB literal を持たない方向へ誘導できること。
- light/dark の token 差分は一箇所で管理し、後続 component が同じ palette を参照できること。
- 実装は Issue #24 の責務に閉じ、`docs/specs/*` の確定済み仕様や feature screen を勝手に変更しないこと。
- Swift の型名、識別子、ファイル名は英語にすること。
- docs 配下の記述は日本語にし、EARS keyword は英語固定にすること。

## 受入基準

- When light mode is active, DesignSystem token API shall return light tokens corresponding to `FM_THEME(false, "indigo")`.
- When dark mode is active, DesignSystem token API shall return dark tokens corresponding to `FM_THEME(true, "indigo")`.
- When accent is requested in either color scheme, DesignSystem token API shall return the Indigo accent family and shall not expose Coral, Teal, or Violet as selectable app accents.
- When shared UI needs background, surface, text, muted, border, star, danger, and scrim colors, DesignSystem token API shall provide named tokens for those roles.
- When a SwiftUI preview or unit-level verification compares light and dark palettes, the two schemes shall differ for background, surface, foreground, muted, border, star, danger, and scrim roles.
- When later feature screens adopt the DesignSystem, they shall be able to reference theme tokens without importing prototype files or duplicating raw color literals.
- The implementation shall remain within `Feedman/DesignSystem` except for minimal project-file wiring if the Xcode project requires the new file to be added.

## 確認事項

- `FM_THEME` の oklch 値から固定 sRGB/P3 値へ変換した最終 hex/RGB 一覧は既存仕様に列挙されていないため、実装時に変換方法と採用値を確認可能な形で残す。
- `accentSoft` の SwiftUI 表現は CSS `color-mix` と完全一致しない可能性があるため、prototype 視覚に近い固定値または透明度付き派生色として扱う。
- status bar style は Issue #24 では token hint の提供までとし、AppShell への適用は後続 Issue の責務とする。
