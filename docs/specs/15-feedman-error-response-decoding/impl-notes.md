# 実装メモ

## 実装内容

- `Feedman/Core/APIError.swift` を追加し、既存 `FeedmanErrorResponse` / `FeedmanErrorBody` / `JSONValue` を利用する `APIResponseDecoder` を定義した。
- 2xx response は指定された success body 型として decode し、失敗時は `FeedmanAPIError.successDecodingFailed` として扱う。
- 非 2xx response は Feedman 標準 error body として decode し、成功時は `FeedmanAPIError.feedmanError` で `statusCode`、`FeedmanErrorBody`、`Retry-After` header を保持する。
- 非 2xx response の error body decode に失敗した場合は `FeedmanAPIError.malformedErrorResponse` とし、`statusCode`、`Retry-After` header、元 body、underlying decode error を保持する。
- `FeedmanErrorContext.retryAfterSeconds` から `details.retry_after_seconds` を参照できるようにした。

## テスト

- `FeedmanTests/APIResponseDecoderTests.swift` を追加した。
- `feedman_error_cooldown.json` fixture を使い、`FEED_COOLDOWN` の `code`、`message`、`category`、`action`、`details`、`Retry-After` header を検証した。
- `details` なしの Feedman error body が typed app error として扱われることを検証した。
- `details` 内の primitive、object、array、null が `JSONValue` として保持されることを検証した。
- 不正 JSON と必須フィールド不足の非 2xx body が `malformedErrorResponse` になることを検証した。
- 2xx success body decode failure が Feedman error decode failure と混同されず、`successDecodingFailed` になることを検証した。

## 検証

- 実行: `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift`
  - 結果: 成功。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 失敗。active developer directory が `/Library/Developer/CommandLineTools` のため、`xcodebuild` が Xcode を要求して終了した。
- 補足: `swiftc` で追加テストファイルの typecheck を試みたが、この環境の Command Line Tools では `XCTest` module を解決できず実行できなかった。

## 確認事項

- `category` と `action` の許容値一覧は仕様で確定していないため、現時点では `String` として扱っている。
- 既存 APIClient が未実装のため、今回は `Data` と `HTTPURLResponse` を受ける最小境界として `APIResponseDecoder` を追加した。将来 APIClient を追加する際はこの boundary を呼び出す想定。
