# Issue #26 実装ノート

## 実装概要

- `Feedman/DesignSystem/ArticleMetadataControls.swift` を追加し、記事カードで再利用する metadata controls を定義した。
- 追加した SwiftUI component:
  - `ArticleStarControl`
  - `ArticleHatebuCountControl`
  - `ArticleSourceRow`
  - `ArticleOpenLinkControl`
- SwiftUI view の直接検査を避けるため、accessibility label、visual state、disabled / hidden / unavailable state、callback guard を `Equatable` な descriptor / state に分離した。
- source row は `FeedmanFaviconView` を利用し、`data:` URL や `nil` の fallback は #25 の favicon component に委譲する。
- 色は `FeedmanTheme` の semantic token を利用し、feature screen 側の raw palette 定義は追加していない。

## スコープ境界

- star / open-link の action は caller-provided closure のみを呼ぶ。
- Repository、network mutation、optimistic update、Safari presentation、既読化、article detail sheet 本体には依存していない。
- hatebu count は `ArticleHatebuCountState.available(Int)` と `.unavailable` で、未取得と `0` 件を区別する。
- open-link は caller が unavailable 時に `.disabled` または `.hidden` を選べる。

## テスト

- `FeedmanTests/ArticleMetadataControlsTests.swift` を追加した。
- 検証観点:
  - starred / unstarred の icon、color role、accessibility label / value。
  - disabled star が action を呼ばないこと。
  - compact / standard / timeline の touch target が安定していること。
  - hatebu unavailable が `-` になり、`0` 件と区別されること。
  - hatebu count `100` 以上が hot / accent state になること。
  - source metadata が favicon URL と relative date を保持できること。
  - open-link が caller-provided action のみを呼び、disabled / hidden 時に action を呼ばないこと。

## 検証結果

- `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 成功。
- `xcrun swiftc -parse Feedman/DesignSystem/ArticleMetadataControls.swift`
  - 成功。
- `xcrun swiftc -parse FeedmanTests/ArticleMetadataControlsTests.swift`
  - 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 未完了。
  - この環境では active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が `tool 'xcodebuild' requires Xcode` として終了した。
  - Xcode が選択された macOS 環境で同コマンドの再実行が必要。

## 確認事項

- `ItemSearchHit` は `hatebu_fetched_at` を含まないため、検索結果で hatebu を表示する場合は caller が `.unavailable` を明示的に渡す実装にした。
- フィード別記事一覧で source row を表示するかどうかは caller が `ArticleSourceRow(metadata: nil)` または metadata 指定で選べる実装にした。
- `link` 欠損時の open-link control は caller が `.disabled` または `.hidden` を選べる実装にした。
- `ItemSummary` の `hatebu_fetched_at` を正式な取得済み判定として使うかは後続の article card 組み込み時に再確認が必要。
