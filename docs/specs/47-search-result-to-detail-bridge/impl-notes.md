# Issue #47 Search result to detail bridge 実装ノート

## 実装概要

- `ItemSearchHit` から `ArticleDetailSheetInput` / `ArticleDetailSummary` を作る mapping を追加し、検索結果 tap から既存 `ArticleDetailSheet` を開くようにした。
- mapping では `publishedAt`、`isDateEstimated`、`isStarred`、`hatebuCount`、`author` など nullable field をそのまま保持し、検索 hit に存在しない `hatebuFetchedAt` は nil にした。
- `AppShellPresentation.articleDetail` を追加し、Root 側で検索結果 selection を sheet presentation state として調停するようにした。
- `AppEnvironment` に `ItemRepository` を追加し、detail fetch / read marking / star mutation は既存 repository 境界を使うようにした。
- 検索結果カードの open-link callback は item id と URL を持つ `SearchResultOpenLinkRequest` に変更し、Root で `openURL` 後に `ItemRepository.updateItemState(isRead: true, isStarred: nil)` を送るようにした。
- 検索結果の open-link URL は http / https かつ host ありの場合だけ有効にした。
- `ArticleDetailViewModel` は read marking 成功時と star mutation 成功時に `ItemStateChange` を通知し、検索画面は現在 visible な results 内の該当 item だけ read / star を反映するようにした。
- 検索結果カードは本文領域だけに detail tap を付け、action row の open-link が card detail action と二重発火しない構造にした。

## テスト

- `AppShellStateTests` に article detail presentation、invalid id no-op、route 変更時の presentation clear、item state change 保持の検証を追加した。
- `GlobalSearchViewModelTests` に nullable search hit の detail input mapping、invalid URL no-op、visible hit の read / star reflection の検証を追加した。
- `ArticleDetailViewModelTests` に read / star 成功時の `ItemStateChange` 通知と search hit summary mapping の検証を追加した。

## 検証結果

- 実行: `xcrun swiftc -parse Feedman/Features/Search/GlobalSearchView.swift Feedman/Features/Search/GlobalSearchViewModel.swift Feedman/Features/ArticleDetail/ArticleDetailViewModel.swift Feedman/Features/AppShell/AppShellState.swift Feedman/Features/AppShell/RootView.swift FeedmanTests/ArticleDetailViewModelTests.swift FeedmanTests/GlobalSearchViewModelTests.swift FeedmanTests/AppShellStateTests.swift`
  - 結果: 成功。
- 実行: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 実行不可。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求して失敗した。

## 確認事項

- 既存コードには `SFSafariViewController` presentation 境界がまだないため、検索結果の元記事 open は #46 と同じ SwiftUI `openURL` 境界を継続利用した。SFSafari 境界が確定した時点で置き換え対象となる。
- 検索結果、詳細、他一覧をまたぐ global item state store は追加していない。状態反映は現在表示中の検索 results と active detail sheet に限定した。

## Reviewer round=1 指摘への是正

- 検索結果の元記事 open 処理を `AppShellSearchResultOpenLinkCoordinator` に切り出し、外部 open、`ItemRepository.updateItemState(isRead: true, isStarred: nil)`、成功時の `ItemStateChange`、失敗時の user-presentable failure を AppShell 境界で検証できるようにした。
- `AppShellStateTests` に、open-link action が外部 open と read marking request を発生させ、detail selection と分離されていることを確認するテストを追加した。
- `AppShellStateTests` に、read marking 失敗時は外部 open 自体をブロックせず、visible search result に `isRead: true` を反映せず、warning failure を表面化することを確認するテストを追加した。
