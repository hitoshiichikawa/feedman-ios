# Issue #43 実装ノート

## 実装内容

- `FeedRepository.registerFeed(url:)` を追加し、`APIClientFeedRepository` で `POST /api/feeds`、`FeedRegistrationRequest { url }`、Bearer 認証、`FeedRegistrationResponse` decode を実装した。
- `RegisteredFeed` domain model を追加し、subscription ID と feed ID を title から分離して保持し、drawer 表示用 `Feed` へ変換できるようにした。
- `APIClientFeedRepository.subscriptions()` を `GET /api/subscriptions` で実装し、登録後の drawer 反映境界と production repository の整合を取った。
- `MockFeedRepository` は登録成功・失敗を差し替え可能にし、成功時は後続 `subscriptions()` に登録 feed を反映する。
- `Feedman/Features/RegisterFeed` に `RegisterFeedViewModel` と `RegisterFeedSheet` を追加した。
- AppShell の「フィードを登録」placeholder sheet を登録 sheet に置換し、成功時に drawer state を upsert して toast を表示するようにした。
- production `AppEnvironment` はログイン後の access token を in-memory provider に保存し、feed repository が real API client と refresh hook を使えるようにした。

## エラー表示

- empty input は repository を呼ばず inline guidance を表示する。
- duplicate は `409`、`duplicate` / `already` / `exists` 系 code、`conflict` category を購読済み guidance にする。
- rate limit は `429`、`FEED_COOLDOWN`、`rate_limit` category を retry-later guidance にし、`retry_after_seconds` または `Retry-After` を表示する。
- invalid URL / validation は `400`、`validation` category、`invalid_url` / `invalid_feed` 系 code を URL 確認 guidance にする。
- auth required、transport failure、generic failure はそれぞれ別 guidance にする。

## 検証

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `swiftc -parse` による変更 Swift ファイルの構文確認: 成功。
- `swiftc -typecheck -parse-as-library` による Core / ViewModel / AppEnvironment の型検査: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 未実行。現在の active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が「requires Xcode」として終了したため。

## 確認事項

- Duplicate / invalid URL の server error code 名は仕様に固定列挙がないため、status code、code、category を組み合わせて保守的に判定している。
- アプリ cold start 時に保存済み refresh token から自動的に authenticated state を復元する処理は既存スコープ外のため追加していない。
