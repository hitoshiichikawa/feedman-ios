# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-08T11:54:29Z -->

## Reviewed Scope

- Branch: codex/issue-14-impl-api-domain-models-and-json-fixtures
- HEAD commit: 80dbe9d14ed219728c9899a275923679b8d1e688
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/Core/APIModels.swift:3` 以降の Codable 型は `design/SPEC-iOS.md` / `design/SERVER.md` の snake_case API 契約に合わせて定義されている。
- 1.2 — `Feedman/Core/APIModels.swift:3`、`:37`、`:73`、`:105`、`:137`、`:149`、`:163`、`:167`、`:171`、`:179`、`:189`、`:203`、`:213`、`:221`、`:229` で v1 API 型を表現している。
- 1.3 — `Feedman/Core/APIModels.swift:11`、`:16`、`:46`、`:51`、`:81`、`:153` は日付系フィールドを `String` / `String?` として保持している。
- 1.4 — `Feedman/Core/APIModels.swift:7`、`:41`、`:77`、`:111` で favicon 系フィールドを `String?` として表現している。
- 1.5 — `Feedman/Core/APIModels.swift:73` の `ItemSearchHit` は `ItemSummary` と別型で、`:77` と `:81` で nullable を表現している。
- 1.6 — `Feedman/Core/APIModels.swift:88` の `ItemSearchHit.CodingKeys` に `hatebu_fetched_at` は含まれていない。
- 1.7 — `Feedman/Core/APIModels.swift:137` と `:149` で `items` / `next_cursor` / `has_more`、横断新着の `since_time` を表現している。
- 1.8 — `Feedman/Core/APIModels.swift:243`、`:247`、`:252` で Feedman error body と `details` を typed decode できる。
- 2.1 — `FeedmanTests/Fixtures/item_summary_nullable_favicon.json` と `APIDomainModelDecodeTests.swift:7` で nullable favicon と RFC3339 string の保持を検証している。
- 2.2 — `FeedmanTests/Fixtures/subscription_error_status.json` と `APIDomainModelDecodeTests.swift:16` で feed status と unread count を検証している。
- 2.3 — `FeedmanTests/Fixtures/item_search_hit_nullable.json` と `APIDomainModelDecodeTests.swift:25` で nullable `published_at` / `favicon_url` を検証している。
- 2.4 — `FeedmanTests/Fixtures/paginated_items_end.json` と `APIDomainModelDecodeTests.swift:33` で pagination fields を検証している。
- 2.5 — `FeedmanTests/Fixtures/cross_feed_items_since_time.json` と `APIDomainModelDecodeTests.swift:44` で `since_time` の RFC3339 文字列保持を検証している。
- 2.6 — `FeedmanTests/Fixtures/feedman_error_cooldown.json` と `APIDomainModelDecodeTests.swift:52` で `details.retry_after_seconds` を参照できることを検証している。
- 2.7 — 追加 fixtures は `example.com`、代表 ID、プレースホルダー token のみで、実 token / Secret / 個人情報は見当たらない。
- 3.1 — `APIDomainModelDecodeTests.swift:7` で `ItemSummary` の nullable favicon fields と RFC3339 strings を検証している。
- 3.2 — `APIDomainModelDecodeTests.swift:16` で `Subscription` の feed status と unread count を検証している。
- 3.3 — `APIDomainModelDecodeTests.swift:25` で `ItemSearchHit` の nullable `published_at` / `favicon_url` を検証している。
- 3.4 — `APIDomainModelDecodeTests.swift:33` で `has_more=false` と `next_cursor=null` の decode を検証している。
- 3.5 — `APIDomainModelDecodeTests.swift:52` で Feedman error body の typed decode を検証している。
- 3.6 — `docs/specs/14-api-domain-models-and-json-fixtures/impl-notes.md` の「検証」に Linux で `xcodebuild` を実行できない制約が明記されている。
- NFR 1.1 — `Feedman/Core/APIModels.swift` は Foundation + `Codable` の Swift 型のみで構成されている。
- NFR 1.2 — 各 `CodingKeys` が API の snake_case JSON keys を decode/encode する。
- NFR 1.3 — fixtures は `FeedmanTests/Fixtures` に集約され、`Feedman.xcodeproj/project.pbxproj` で test resources に追加されている。
- NFR 2.1 — 差分は API model、fixtures、decode tests、Xcode project 登録、Issue spec notes に閉じており、APIClient / Repository / Feature 実装は含まれていない。
- NFR 2.2 — 確定済みの `design/SPEC-iOS.md` / `design/SERVER.md` は変更されていない。

## Findings

なし

## Summary

`git diff --stat develop..HEAD` とファイル単位差分を確認し、対象 AC の実装・fixture・decode test は確認できた。`tasks.md` と `design.md` は存在しないため、`_Boundary:_` アノテーションに基づく境界照合は実施できなかったが、差分パスは requirements の実装境界から外れていない。

RESULT: approve
