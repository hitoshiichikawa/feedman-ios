# Issue #33 実装メモ

## 実装内容

- `TimelineViewModel.loadNextPageIfNeeded(currentItemID:)` の sentinel 判定を、末尾 5 件ではなく最後に描画された item のみに変更した。
- refresh 成功時に既存 items を first page snapshot で置き換え、`canLoadMore` と empty / loaded state を snapshot に合わせる既存挙動をテストで固定した。
- refresh 成功時に refresh error / next-page error feedback が消えることをテストで固定した。
- refresh 失敗時に既存 items を保持し、items がない場合は recoverable initial error state になることをテストで固定した。
- next page 成功時の snapshot order 反映、失敗時の既存 items / `canLoadMore` 保持、retry 成功時の error clearing をテストで固定した。
- first-page loading 中の重複 refresh、refresh 中の next page request、next-page loading 中の重複 next page request を suspend 可能な mock repository で検証した。
- terminal state では last item appear が発生しても next page request を出さない既存挙動を維持した。

## 検証

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 失敗。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため `xcodebuild` が実行できなかった。
  - エラー: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`
- 代替確認として、差分レビューにより Timeline feature が `FeedRepository.loadCrossFeedFirstPage` / `loadCrossFeedNextPage` のみを使い、View 層で cursor / `since_time` / endpoint path を構築していないことを確認した。

## 確認事項

なし
