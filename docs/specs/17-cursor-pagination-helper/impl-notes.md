# 実装メモ

## 実装内容

- `Feedman/Core/Pagination/CursorPaginationState.swift` を追加し、一覧系で共通利用できる generic な cursor pagination state helper を実装した。
- helper は蓄積済み `items`、次回 request 用 `nextCursor`、追加ページ取得可否 `canLoadMore` を保持する。
- `applyFirstPage(_:)` は first page の items で蓄積状態を置き換え、`appendPage(_:)` は追加 page の items を末尾に追加する。
- `resetForRefresh()` は refresh 開始時に items と cursor を初期化し、`canLoadMore` を初期状態の `true` に戻す。
- `hasMore == true` かつ空でない `nextCursor` の場合のみ次 cursor を公開する。それ以外の `hasMore == false`、`nextCursor == nil`、`nextCursor == ""` は終端として扱う。
- `CursorPaginatedPage` protocol を追加し、既存の `CursorPaginatedResponse` と `CrossFeedItemsResponse` から helper を更新できるようにした。`sinceTime` など endpoint 固有の付加情報は helper では解釈しない。

## テスト

- `FeedmanTests/CursorPaginationStateTests.swift` を追加した。
- 初期状態で items が空、cursor が未指定、追加ページ取得可能であることを検証した。
- first page 適用時の items 蓄積と next cursor 公開を検証した。
- additional page 適用時に既存 items の後ろへ append されることを検証した。
- `hasMore == false`、`nextCursor == nil`、`nextCursor == ""` の終端判定を検証した。
- refresh reset で items と cursor が初期化され、`canLoadMore` が初期状態へ戻ることを検証した。
- refresh 後の first page 適用で reset 前の items が残らないことを検証した。
- 既存の `CursorPaginatedResponse` から generic state を更新できることを検証した。

## 検証結果

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は、active developer directory が `/Library/Developer/CommandLineTools` であり Xcode ではないため実行できなかった。
- 代替として `xcrun swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/Pagination/CursorPaginationState.swift` を実行し、Core helper と既存 API model の typecheck が成功した。
- `plutil -lint Feedman.xcodeproj/project.pbxproj` を実行し、project file の構文検証が成功した。

## 確認事項

- Issue #17 の範囲内で追加確認が必要な未決事項はない。
- Xcode / iOS Simulator での XCTest 実行は環境制約により未実施。macOS/Xcode 環境で `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を再実行する必要がある。
