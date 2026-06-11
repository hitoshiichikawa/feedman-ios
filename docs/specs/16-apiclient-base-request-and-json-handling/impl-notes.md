# 実装メモ

## 実装内容

- `Feedman/Core/APIClient.swift` を追加し、`baseURL`、差し替え可能な `APITransport`、`JSONEncoder`、`APIResponseDecoder` を初期化時に受け取る薄い API client を実装した。
- `URLSession` を `APITransport` に適合させ、Repository 実装では実 transport、単体テストでは mock transport を注入できる境界にした。
- `HTTPMethod` は v1 API で使う `GET`、`POST`、`PUT`、`DELETE` を定義した。
- request ごとの `accessToken` 引数で `Authorization: Bearer <token>` を付与する形に留め、自動 refresh、TokenStore、Keychain、AuthRepository は実装していない。
- JSON endpoint 共通 header として `Accept: application/json` を付与し、body がある場合のみ `Content-Type: application/json` と encoded JSON body を設定する。
- response decode は既存 `APIResponseDecoder` を呼び出し、2xx success decode と非 2xx Feedman error mapping の typed contract を維持した。
- `FeedmanAPIError` に APIClient transport 層用の `invalidRequestURL(path:)`、`nonHTTPResponse(_:)`、`transportFailed(underlyingError:)` を追加し、non-HTTP response と transport thrown error の元情報を保持できるようにした。
- `FeedmanTests/APIClientTests.swift` を追加し、base URL 解決、query encode、認証 header、JSON body、success decode、Feedman error decode、`429 / FEED_COOLDOWN` retry metadata、malformed error response、non-HTTP response、transport thrown error を mock transport で検証するテストを追加した。
- `Feedman.xcodeproj/project.pbxproj` に `APIClient.swift` と `APIClientTests.swift` を登録した。

## 設計上の判断

- access token は request ごとの optional 引数で渡す API にした。#19 の TokenStore や後続 AuthRepository と責務が重ならないよう、token provider protocol や 401 refresh retry はこの Issue では導入していない。
- endpoint path の先頭 `/` と `baseURL` の trailing slash は APIClient 内で正規化し、`/api/...` の仕様 path を壊さず absolute URL を生成する。
- query は `URLQueryItem` 引数と、`path` 内の `?q=...` の両方を扱う。raw query は `URLComponents.query` として取り込み、空白、`|`、日本語を URL encode させる。
- 204 No Content 専用の response 型や専用 method は requirements の範囲外のため追加していない。

## 検証

- `xcrun swiftc -typecheck -parse-as-library Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift`
  - 成功。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 失敗。現在の環境は Xcode ではなく Command Line Tools が active developer directory になっているため、`xcodebuild` が実行できない。
  - エラー: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`
- 追加確認として `@testable import Feedman` 用の一時 module を作って `FeedmanTests/APIClientTests.swift` の型チェックを試したが、同じ CLT 環境に `XCTest` module がなく失敗した。
  - エラー: `FeedmanTests/APIClientTests.swift:1:8: error: no such module 'XCTest'`

## 未実施

- Xcode / iOS Simulator 環境での XCTest 実行は未実施。macOS/Xcode 環境で `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を再実行する必要がある。
