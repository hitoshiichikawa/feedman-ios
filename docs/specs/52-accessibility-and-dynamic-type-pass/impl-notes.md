# Issue #52 Accessibility and Dynamic Type pass 実装メモ

## Implementation Notes

採用方針:

- Full App Store accessibility audit には広げず、primary v1 flows の VoiceOver label と larger Dynamic Type の薄い横断 pass に閉じた。
- 既存の DesignSystem と feature-local descriptor を維持し、新しい app-wide accessibility framework や global state は追加しない。
- Dynamic Type の実レイアウトは XCTest だけで完全検証できないため、production code は shared helper で分岐し、descriptor / helper の文字列と状態を unit test で固定した。

主な実装:

- `FeedmanAccessibilityLayout` を追加し、`.accessibility1` 以上で primary action の行数制限を外し、横並び control を縦積みに切り替える判定を共有化した。
- `FeedmanPrimaryButtonStyle` / `FeedmanSecondaryButtonStyle` は accessibility Dynamic Type で primary action text が 2 行制限に縛られないようにした。
- `FeedmanBannerView` は accessibility Dynamic Type で message と action を縦積みにし、warning / retry banner の文言と action が横方向で競合しないようにした。
- `ArticleSourceRow` は accessibility Dynamic Type で favicon + feed title と relative date を縦に分け、source row が star / open-original controls を圧迫しにくい layout にした。
- `ArticleDetailLoadedContent` の metadata line は accessibility Dynamic Type で hatebu / author / 推定日時を縦積みにし、長い author text が他の metadata と重ならないようにした。
- `ArticleDetailFooter` は accessibility Dynamic Type で「元記事を開く」primary action と star control を縦積みにし、sheet footer の primary action と icon-only control が競合しないようにした。
- `RegisterFeedSheet` と `SubscriptionSettingsSheet` の primary / resume action text は 1 行固定を避け、折り返し可能にした。
- `SearchResultRowDescriptor.detailAccessibilityLabel` を追加し、検索結果の detail tap area が action、title、feed、published time、read state を読み上げられるようにした。
- `GlobalSearchView` は検索結果の detail tap area に descriptor の accessibility label を接続した。
- `ArticleOpenLinkControlDescriptor` の enabled state が「元記事をブラウザで開く」semantics を持つことを test で固定した。

## Tests

追加 / 更新した主な assertion:

- `ArticleMetadataControlsTests`
  - accessibility Dynamic Type で stacked layout を使う判定。
  - accessibility Dynamic Type で primary action line limit を外す判定。
  - open-original icon-only control の label / symbol / enabled / visible state。
- `GlobalSearchViewModelTests`
  - search result detail accessibility label が action、article title、feed title、published time、read state を含むこと。

検証:

- `git diff --check`: 成功。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/ArticleMetadataControlsTests -only-testing:FeedmanTests/GlobalSearchViewModelTests test`: 30 tests 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 381 tests 成功。

備考:

- `xcodebuild` を素で実行すると active developer directory が `/Library/Developer/CommandLineTools` のため失敗する環境だが、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を明示して指定コマンド相当の full test を実行できた。
- build 中に既存 `FeedmanToastCenter` 由来の `no 'async' operations occur within 'await' expression` warning が出た。本 Issue の変更による新規 warning ではない。

## 手動確認観点

- VoiceOver: Login / AppShell drawer / Timeline / Feed / Starred / Search / Article detail / Register feed / Subscription settings / Account の primary controls が日本語 label と状態を読み上げること。
- Dynamic Type: `.accessibility3` 以上で banner action、article source row、article detail metadata、article detail footer、feed registration submit、subscription settings save/resume が重ならず、スクロールまたは縦方向の伸長で到達できること。
- Search result: detail tap area が「記事詳細を開く」に加えて title、feed、published time、既読/未読を読み上げ、open-original control と混同しないこと。

## 確認事項

- VoiceOver の実機 / Simulator 手動確認はこの Stage A では未実施。Reviewer または後続 QA で上記手動確認観点を確認する。
- larger Dynamic Type の必須確認カテゴリは requirements の未確定事項どおり未決。実装は `.accessibility1` 以上を stacked layout の対象にした。
