# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-11T22:51:43Z -->

## Reviewed Scope

- Branch: codex/issue-30-impl-toolbar-entry-points-for-search-theme-ac
- HEAD commit: f198564e9f88b30091478b3079ae7d3d1ce4e1db
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `RootView.swift:57` / `RootView.swift:59` / `RootView.swift:67` で menu、route title、検索・テーマ toolbar action を同一 NavigationStack toolbar に配置。long title / Dynamic Type は `impl-notes.md` の manual verification point に明記。
- 1.2 — `RootView.swift:68` / `AppShellState.swift:137` で検索 toolbar tap が `.search` route を選択。
- 1.3 — `AppShellState.swift:129` の単一 `currentRoute` 更新と `AppShellStateTests.testActivatingSearchFromSearchKeepsSingleRouteAndClearsPresentation` で重複 navigation state を作らないことを確認。
- 1.4 — `RootView.swift:75` / `AppShellState.swift:155` で theme toolbar tap が explicit override state を更新。
- 1.5 — `RootView.swift:91` / `RootView.swift:568` で `.system` 時は `preferredColorScheme` を `nil` にし、system appearance follow を維持。
- 1.6 — `RootView.swift:91` と `FeedmanTheme` semantic token 利用箇所により toolbar、drawer、scrim、placeholder、sheet surface が同じ color scheme に従う。
- 1.7 — `RootView.swift:73` / `RootView.swift:80` で toolbar action に日本語 accessibility label を付与。
- 1.8 — iOS 標準 `navigationTitle` / `ToolbarItemGroup` 構成で title truncation と trailing actions を扱い、`impl-notes.md` に manual verification point を記載。
- 2.1 — `RootView.swift:371` で drawer footer に account entry point を表示。
- 2.2 — `RootView.swift:37` / `AppShellState.swift:141` と `AppShellStateTests.testPresentingAccountClosesDrawerAndUsesSinglePresentationState` で account sheet state と drawer close を確認。
- 2.3 — `RootView.swift:378` で drawer footer に theme action を表示。
- 2.4 — `RootView.swift:40` / `AppShellState.swift:155` で drawer footer theme action が toolbar と同じ theme override state を更新。
- 2.5 — `RootView.swift:387` で `フィードを登録` entry point を表示。
- 2.6 — `RootView.swift:43` / `AppShellState.swift:146` と `AppShellStateTests.testPresentingFeedRegistrationClosesDrawerAndReplacesPresentationState` で feed registration sheet state と drawer close を確認。
- 2.7 — `RootView.swift:273` 以降の scroll content で primary routes、feed section、footer を分け、`RootView.swift:365` の footer 冒頭に Divider を置いている。
- 2.8 — 差分内に keyword notification entry point はなく、drawer footer は account / theme / feed registration のみ。
- 3.1 — `RootView.swift:122` で search route placeholder が `検索` を表示し、API integration を含まない。
- 3.2 — `RootView.swift:193` / `RootView.swift:610` で account placeholder が実 user data、logout、revoke、delete-account behavior を持たない説明に留まる。
- 3.3 — `RootView.swift:193` / `RootView.swift:614` で feed registration placeholder が network submission を行わない説明に留まる。
- 3.4 — `RootView.swift:84` / `RootView.swift:193` と `FeedmanSheetShell` の dismiss button により native sheet と dismiss affordance を提供。
- 3.5 — `AppShellState.swift:137` / `AppShellState.swift:109` / `AppShellState.swift:113` で route placeholder が explicit state、title、drawer selection source に接続。
- 3.6 — `AppShellState.swift:94` の単一 `activePresentation` と `sheet(item:)` により duplicate sheet stack を作らず、presentation replacement は test 済み。
- 3.7 — `RootView.swift:126` / `RootView.swift:612` / `RootView.swift:615` で後続 Issue 実装であることと real API behavior がないことを明記。
- 4.1 — `AppShellState.swift:101` の default `.system` と `RootView.swift:568` の `nil` preferredColorScheme で起動時は system follow。
- 4.2 — `AppShellState.swift:79` と `AppShellStateTests.testThemeOverrideCyclesThroughSystemDarkAndLight` で `system -> dark -> light -> system` cycle を確認。
- 4.3 — `RootView.swift:75` / `RootView.swift:40` が同じ `AppShellState.themeOverride` を更新。
- 4.4 — `RootView.swift:91` で AppShell 全体へ preferred color scheme を適用。
- 4.5 — `AppShellStateTests.testThemeOverrideDoesNotChangeRouteOrDrawerState` で drawer open 中の theme change が route / drawer state を変えないことを確認。
- 4.6 — session-local state として `AppShellState.themeOverride` が deterministic に動作し、永続化なしでも current session で予測可能。
- 4.7 — 差分は accent picker や `FeedmanTheme` token redefine を追加していない。
- 5.1 — `RootView.swift:73` / `RootView.swift:80` / `RootView.swift:384` / `RootView.swift:550` で toolbar と drawer footer action に日本語 label を付与。
- 5.2 — `FeedmanSheetShell` の title header と `閉じる` dismiss accessibility label を account / feed registration sheet が利用。
- 5.3 — `RootView.swift:52` / `RootView.swift:53` で drawer closed 時は hidden footer actions を hit testing / accessibility 対象から外す。
- 5.4 — `RootView.swift:15` / `RootView.swift:16` で drawer open 時に main content を accessibility hidden にし、`RootView.swift:273` の scroll order で footer actions が primary navigation items の後に到達可能。
- 5.5 — `RootView.swift:273` の ScrollView と `RootView.swift:527` / `RootView.swift:534` の multiline footer labels により大きい Dynamic Type で読める構成。`impl-notes.md` に manual verification point も追加済み。
- 5.6 — toolbar、drawer footer、placeholder、sheet は `FeedmanTheme` semantic tokens と既存 `FeedmanSheetShell` を利用。
- 6.1 — 実装差分は `Feedman/Features/AppShell`、`FeedmanTests`、spec notes に限定されている。
- 6.2 — `AppShellStateTests.swift:70` / `AppShellStateTests.swift:92` / `AppShellStateTests.swift:102` / `AppShellStateTests.swift:121` / `AppShellStateTests.swift:134` で state helper の search、account / registration presentation、drawer close、theme transition を確認。
- 6.3 — `impl-notes.md` に SwiftUI layout / sheet presentation の manual verification points が記載され、前回指摘の long title / footer reachability / Dynamic Type readability も含まれる。
- 6.4 — reviewer でも `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行し、Command Line Tools 環境のため失敗することを確認。
- 6.5 — `impl-notes.md` に Xcode.app が利用できず test 実行不能だった制約が明記されている。

## Findings

なし

## Summary

round 1 の footer 到達性 / Dynamic Type / manual verification point の指摘は、ScrollView 化と `impl-notes.md` 追記で解消済み。`tasks.md` と `design.md` は spec dir に存在しなかったため確認対象外。`xcodebuild` は実装メモ通り Command Line Tools 環境で実行不能だったが、AC カバレッジ、必要な state helper test、実装境界に reject 対象は見つからない。

RESULT: approve
