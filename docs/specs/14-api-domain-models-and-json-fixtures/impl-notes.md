# 実装メモ

## 実装概要

- `design/SPEC-iOS.md` と `design/SERVER.md` の API 契約を優先し、`Feedman/Core/APIModels.swift` に v1 API domain model を追加した。
- 既存の `Feed` / `FeedItem` / `FeedStatus` は mock app model として維持し、既存 `MockFeedRepository` と `RootView` に影響しないよう API 型を別ファイルで定義した。
- 日付系フィールドは `Date` へ変換せず、RFC3339 の `String` として保持する。
- `feed_favicon_url` / `favicon_url` は `String?` として扱い、`data:` URL と `null` を保持できるようにした。
- `Subscription.feedFaviconURL` は `/api/subscriptions` の `favicon_url` を decode する。
- `FeedRegistrationResponse` は `POST /api/feeds` の flat な feed response として定義し、未確認の `subscription` wrapper は固定しない。
- `ItemSearchHit` は `ItemSummary` と別 struct とし、`published_at` / `favicon_url` の `null` を許容し、`hatebu_fetched_at` を要求しない。
- Feedman error body の `details` は `[String: JSONValue]` として保持し、`retry_after_seconds` のような追加情報を参照できるようにした。

## 変更ファイル

- `Feedman/Core/APIModels.swift`
- `FeedmanTests/APIDomainModelDecodeTests.swift`
- `FeedmanTests/Fixtures/item_summary_nullable_favicon.json`
- `FeedmanTests/Fixtures/subscription_error_status.json`
- `FeedmanTests/Fixtures/feed_registration_response.json`
- `FeedmanTests/Fixtures/item_search_hit_nullable.json`
- `FeedmanTests/Fixtures/paginated_items_end.json`
- `FeedmanTests/Fixtures/cross_feed_items_since_time.json`
- `FeedmanTests/Fixtures/feedman_error_cooldown.json`
- `Feedman.xcodeproj/project.pbxproj`
- `docs/specs/14-api-domain-models-and-json-fixtures/requirements.md`
- `docs/specs/14-api-domain-models-and-json-fixtures/impl-notes.md`

## 検証

- `jq empty FeedmanTests/Fixtures/*.json` で fixture JSON の妥当性を確認した。
- `git diff --check` で差分の空白エラーがないことを確認した。
- この Linux 環境には `swiftc` が無く、`swiftc -parse Feedman/Core/APIModels.swift` は実行できなかった。
- この Linux 環境には `xcodebuild` が無く、以下の XCTest は実行できなかった。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- この Linux 環境には `plutil` が無く、`project.pbxproj` の lint は実行できなかった。

## 確認事項

- `Subscription.feed_status` の許容値は `active` / `stopped` / `error` として実装した。status に付随する message/error reason の最終フィールド名はサーバー実装または追加仕様で確認が必要。
- `UserResponse` は `id` / `email` / `name` / `avatar_url` の最小形で定義した。`/auth/me` の実 response に追加フィールドがある場合は後続 Issue で拡張する。
