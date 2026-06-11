# Issue #24 Feedman theme tokens 実装メモ

## 実装概要

- `Feedman/DesignSystem/FeedmanTheme.swift` に light/dark の semantic token を追加した。
- SwiftUI から直接使う `Color` token と、単体テストで固定値を検証できる `ResolvedTokens` を同じ定義から提供する。
- 既存呼び出し互換のため、`FeedmanTheme.accent`、`FeedmanTheme.star`、`FeedmanTheme.background`、`FeedmanTheme.surface`、`FeedmanTheme.mutedText` は残した。
- `ColorScheme` 明示利用向けに `tokens(for:)` と `resolvedTokens(for:)` を追加した。
- 静的 `Color` token は `UIColor` の dynamic provider で light/dark trait に追従する。
- Coral、Teal、Violet は実装していない。

## OKLCH 変換と採用値

`design/mobile/fm-data.jsx` の `FM_THEME(false/true, "indigo")` を元に、OKLab/OKLCH から sRGB へ変換した固定近似値を採用した。グレースケール、star、danger、dark accent は OKLCH 変換値を採用している。

Light accent は `design/SPEC-iOS.md` §8 の確定値を優先し、`FM_THEME` の `oklch(0.55 0.17 264)` 単純変換ではなく `#4F46E5` を採用した。

| Token | Light | Dark | Source |
|---|---:|---:|---|
| `background` | `#FAFAFA` | `#0A0A0A` | `bg` |
| `surface` | `#FFFFFF` | `#171717` | `surface` |
| `surfaceSecondary` | `#F7F7F7` | `#1E1E1E` | `surface2` |
| `foreground` | `#171717` | `#FAFAFA` | `fg` |
| `muted` | `#F5F5F5` | `#262626` | `muted` |
| `mutedForeground` | `#737373` | `#A1A1A1` | `mutedFg` |
| `border` | `#E5E5E5` | `#FFFFFF` / 12% | `border` |
| `borderStrong` | `#D4D4D4` | `#FFFFFF` / 20% | `borderStrong` |
| `accent` | `#4F46E5` | `#6895F4` | Indigo |
| `accentOn` | `#FFFFFF` | `#FFFFFF` | `accentOn` |
| `accentSoft` | `#E6EAFF` | `#6895F4` / 18% | `accentSoft` |
| `star` | `#E7AD01` | `#F5BA26` | `star` |
| `danger` | `#E7000F` | `#FF6468` | `danger` |
| `scrim` | `#000000` / 32% | `#000000` / 60% | `scrim` |

## `accentSoft` の近似

- Light `accentSoft` は `#4F46E5` を OKLCH 化し、`color-mix(in oklch, accent 12%, white)` 相当に寄せた固定近似 `#E6EAFF` とした。
- Dark `accentSoft` は prototype の `color-mix(in oklch, accent 18%, transparent)` に合わせ、dark accent `#6895F4` の 18% opacity とした。
- SwiftUI runtime では OKLCH や CSS `color-mix` を使わない。

## テスト

- `FeedmanTests/FeedmanTests.swift` に theme token の固定値検証を追加した。
- light/dark で主要 semantic role が異なることを検証した。

## 確認事項

- light accent は仕様確定値 `#4F46E5` を優先したため、`FM_THEME` の light accent OKLCH 値を機械変換した色とは完全一致しない。
- `accentSoft` は SwiftUI 固定近似であり、ブラウザの CSS `color-mix(in oklch, ...)` とピクセル完全一致する保証はない。
- status bar style の適用は行っていない。Issue #24 では `usesDarkChrome` token hint の提供までとした。
