# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-11T22:43:23Z -->

## Reviewed Scope

- Branch: codex/issue-29-impl-drawer-feed-list-with-mock-repository
- HEAD commit: 8645e2596ebd1e4839a82d024a02af195190bb1d
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `RootView.swift:66` / `AppShellDrawerFeedState.swift:30` で app shell 表示時に `FeedRepository.subscriptions()` を呼び、`AppShellPreviewData.drawerFeeds` は削除されている。
- 1.2 — `RootView.swift:227` で `feedSectionState.feeds` を drawer row に描画し、`AppShellDrawerFeedStateTests.swift:6` で mock repository の表示値を検証している。
- 1.3 — `RootView.swift:231` から `:233` で feed の stable `id` と title を `AppShellRoute.feed(id:title:)` に渡し、`AppShellDrawerFeedStateTests.swift:68` で検証している。
- 1.4 — `AppShellDrawerFeedState.swift:34` から `:36` で load 成功ごとに repository 戻り値で state を更新し、hardcoded preview entries を使っていない。
- 1.5 — `RootView.swift:227` で `ForEach` の描画 id を index にして duplicate feed id での crash を避け、route は各 row の feed 値から決定している。
- 2.1 / 2.2 — `RootView.swift:387` から `:397` で `unreadCount > 0` の場合のみ badge を表示している。
- 2.3 — `RootView.swift:431` から `:442` で unread count を日本語の accessibility value に含めている。
- 2.4 / 2.5 — `RootView.swift:367` から `:401` で avatar、title/status、badge を HStack/VStack と lineLimit で配置し、Dynamic Type 時も truncation/wrapping 可能な構成にしている。
- 3.1 / 3.2 / 3.3 — `RootView.swift:420` から `:428` で active は nil、stopped は `停止中`、error は `取得エラー` に変換している。
- 3.4 / 3.5 — status message は action に使わず、`RootView.swift:231` から `:233` で stopped/error も通常の feed route として選択している。
- 4.1 / 4.5 — `RootView.swift:202` から `:214` と `:243` から `:248` で global route entries は feed section state と独立して選択可能。
- 4.2 — `RootView.swift:286` から `:301` と `AppShellDrawerFeedState.swift:31` から `:32` で初回 loading 表示と既存 feed list 保持を扱っている。
- 4.3 / 4.4 — `RootView.swift:304` から `:318` で empty と failed を feed section 内の非 blocking 表示として扱い、`AppShellDrawerFeedStateTests.swift:29` と `:44` で state を検証している。
- 4.6 — `RootView.swift:105` から `:119` で feed route が現 loaded feed list に存在しない場合は placeholder fallback を表示している。
- 5.1 / 5.2 / 5.3 / 5.4 / 5.5 — current `Feed` model に favicon field がないため、`RootView.swift:410` から `:418` で title-derived の固定寸法 avatar に留め、`AsyncImage(url:)` は追加していない。
- 6.1 — `RootView.swift:202` から `:214`、`:220` から `:239`、`:243` から `:248` で `すべての新着`、`お気に入り`、フィード一覧、`アカウント` を維持している。
- 6.2 / 6.3 / 6.4 / 6.5 — 差分内に keyword notification entry、subscription settings action、prototype JSON field、`favicon_letter` / `favicon_color` の追加はない。
- 7.1 — `AppShellDrawerFeedStateTests.swift:80` から `:89` の stub repository で unit tests を構成し、実 network / Keychain に依存していない。
- 7.2 — `AppShellDrawerFeedStateTests.swift:14` から `:27` で title、unread count、status の保持を検証している。
- 7.3 — `AppShellDrawerFeedStateTests.swift:29` から `:42` で empty state と current route / drawer state の維持を検証している。
- 7.4 — `AppShellDrawerFeedStateTests.swift:44` から `:55` で failure state と global route selection 継続を検証している。
- 7.5 — `AppShellDrawerFeedStateTests.swift:68` から `:73` で stable id と title の route 変換を検証している。
- 7.6 / 7.7 — `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は reviewer 環境でも Command Line Tools のため実行不可。`impl-notes.md` に同制約が明記されている。

## Findings

なし

## Summary

`git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` は取得済み。指定された `tasks.md` と `design.md` は存在しなかったため、boundary は `requirements.md` の scope / non-scope と差分で照合した。
`xcodebuild` は active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。`git diff --check develop..HEAD` と `plutil -lint Feedman.xcodeproj/project.pbxproj` は成功。

RESULT: approve
