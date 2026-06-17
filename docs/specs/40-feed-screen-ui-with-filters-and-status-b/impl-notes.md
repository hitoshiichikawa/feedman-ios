# Issue #40 実装メモ

## 実装内容

- `Feedman/Features/Feeds` にフィード別記事一覧の SwiftUI screen / ViewModel を追加した。
  - `FeedViewModel` は `FeedRepository.loadFeedItemsFirstPage(feedID:filter:limit:)` / `loadFeedItemsNextPage()` を利用する。
  - 初回読み込み、filter 切替、empty、initial error、next page、next page error、local-only star toggle、status banner descriptor を扱う。
  - feed id が変わった場合は filter を `all` に戻し、新しい feed id の first page を読み込む。
- `FeedView` を追加し、以下を表示するようにした。
  - stopped/error feed の inline status banner と `再開` action affordance。
  - `すべて` / `未読` / `スター` の segmented picker。
  - loading / empty / recoverable error / compact loading row / retry banner。
  - favicon/source row、相対日時、title、summary、はてブ数、star、external link affordance を持つ article card。
- `RootView` の feed route placeholder を `FeedView` へ差し替えた。
  - `再開` action は mutation を呼ばず、toast で「後続の購読設定で対応」と表示する。
- `FeedViewModelTests` を追加した。
  - success / empty / initial error retry。
  - filter change reload と same filter no-op。
  - selected feed change。
  - next page success / failure retry / terminal no-op。
  - stopped/error banner descriptor と fallback message。
  - resume action intent が repository mutation を呼ばないこと。
  - card descriptor の relative date、summary trim、opacity、hatebu、link、intent 分離。
  - local star toggle が repository mutation を呼ばないこと。
- `Feedman.xcodeproj/project.pbxproj` に `FeedViewModel.swift`、`FeedView.swift`、`FeedViewModelTests.swift` を登録した。

## スコープ制御

- Manual fetch cooldown、`POST /api/subscriptions/{id}/fetch`、`POST /api/subscriptions/{id}/resume`、settings mutation は実装していない。
- 記事詳細 sheet、既読 API、スター更新 API、SFSafariViewController presenter の追加は行っていない。
- #39 repository contract と Core API model は変更していない。

## 検証結果

- 成功: `plutil -lint Feedman.xcodeproj/project.pbxproj`
- 成功: `xcrun swiftc -frontend -parse Feedman/Features/Feeds/FeedViewModel.swift Feedman/Features/Feeds/FeedView.swift FeedmanTests/FeedViewModelTests.swift Feedman/Features/AppShell/RootView.swift`
- 実行不可: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`tool 'xcodebuild' requires Xcode` により失敗した。
- 実行不可: Swift full typecheck
  - 理由: この CommandLineTools 環境では iOS/UIKit SDK が解決できず、`no such module 'UIKit'` で失敗する。

## 確認事項

- `再開` action の最終導線は未確定。本 Issue では intent / affordance と toast 表示に留めた。
- Pull-to-refresh は SPEC 上 feed manual fetch だが、Issue スコープ外のため実装していない。
- SwiftUI layout / Dynamic Type / Preview は Xcode 環境での確認が必要。
