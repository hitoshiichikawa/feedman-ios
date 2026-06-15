# Issue #32 実装ノート

## 実装内容

- `Feedman/Features/Timeline/TimelineViewModel.swift` を追加し、横断タイムラインの初回読み込み、pull-to-refresh、追加読み込み、終端、初回エラー、追加読み込みエラーを ViewModel state として扱うようにした。
- `FeedRepository.loadCrossFeedFirstPage` / `loadCrossFeedNextPage` のみを使い、Timeline View / ViewModel では `/api/items/cross-feed` の query を組み立てない。
- `Feedman/Features/Timeline/TimelineView.swift` を追加し、`ArticleSourceRow`、`ArticleHatebuCountControl`、`ArticleStarControl`、`ArticleOpenLinkControl`、`FeedmanTheme`、shared loading / empty / error / banner primitives を組み合わせたカード型一覧を表示するようにした。
- AppShell の `.timeline` route を `TimelineView` に差し替え、`RootView` が `TimelineViewModel` を保持することで drawer 開閉や同一 shell session の route 復帰で状態を保つようにした。
- `ItemSummary.publishedAt` は RFC3339 `String` のまま保持し、表示用の小さな `TimelineRelativeDateFormatter` で相対日時へ変換するようにした。
- カード tap は `selectedItemID` / `onSelectItem` の intent に留め、記事詳細 sheet と既読化 sync は実装していない。
- Star は server sync なしのローカル UI 更新に留め、pagination snapshot で同じ item が返ってもローカルの star 表示を維持するようにした。
- Open link は `URL` として妥当な http / https link の場合のみ既存 `openURL` 境界へ渡し、既読化 sync は実装していない。

## テスト

- `FeedmanTests/TimelineViewModelTests.swift` を追加した。
- 初回 success / empty / error / retry、refresh failure 時の既存 item 保持、next page success / failure / retry、terminal state で追加読み込みしないことを検証した。
- local star toggle が repository mutation を呼ばず、次ページ snapshot 後も表示上維持されることを検証した。
- card descriptor で read opacity、summary nil/blank、hatebu available/unavailable、estimated relative date、不正 link、selection/star/open-link intent 分離を検証した。

## 実行した確認

- `plutil -lint Feedman.xcodeproj/project.pbxproj` は成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は、この環境の active developer directory が `/Library/Developer/CommandLineTools` で Xcode ではないため実行できなかった。

## 残した確認事項

- macOS/Xcode 環境で `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行する必要がある。
- 記事詳細 sheet、既読化、real star mutation sync、SFSafariViewController presenter は本 Issue のスコープ外として未実装。
