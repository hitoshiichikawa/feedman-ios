# Issue #25 実装メモ

## 実装内容

- `Feedman/DesignSystem/FeedmanFaviconView.swift` を追加し、`data:<mime>;base64,...` 形式の favicon を `Data(base64Encoded:)` と `UIImage(data:)` で decode して SwiftUI の `Image` として表示する component を実装した。
- `AsyncImage` は使用せず、remote URL の取得・cache・retry は実装していない。
- `nil`、空文字、`data:` 以外、`;base64,` がない data URL、不正 base64、非 image MIME、`UIImage` 化できない payload は letter avatar fallback になる。
- fallback は表示名を trim し、先頭の user-visible character を大文字化して表示する。表示名が空または `nil` の場合は `?` を使う。
- avatar 背景色は固定 palette と固定 FNV-1a 風 hash で選択し、同じ表示名では同じ色になるようにした。
- `size` と `cornerRadius` を指定でき、画像状態と fallback 状態のどちらも同じ正方形 frame と corner radius を使う。
- `FeedmanTests/FeedmanFaviconViewTests.swift` を追加し、data URL decode、invalid fallback 条件、letter derivation、deterministic color selection を XCTest で検証するようにした。
- `Feedman.xcodeproj/project.pbxproj` に新規 source/test file を登録した。

## 検証

- 実行済み: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: OK
- 実行不可: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode を要求して失敗した。
  - エラー: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

## 確認事項

- Issue #25 の scope に合わせ、Feature screen への組み込み、API model、repository、network、auth は変更していない。
- favicon 表示の API 契約は `docs/specs/25-favicon-data-url-and-letter-avatar-view/requirements.md` に従い、`data:<mime>;base64,...` または fallback のみに限定した。
