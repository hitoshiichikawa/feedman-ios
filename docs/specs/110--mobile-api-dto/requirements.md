# Requirements Document

## Introduction

Issue #110 は、iOS 側の article / search / feed registration 周辺 DTO と request construction を、サーバ側 Issue hitoshiichikawa/feedman#207 で明文化された v1 モバイル API 契約へ揃えるための要件である。
既存の #31 / #46 / #43 では初期 fixture や古い mock shape を前提にした箇所があり、`since_time` query、`scope=global`、subscription 形の登録レスポンスなどが実サーバ契約とずれている。
本要件ではサーバ契約に対して decode / 表示 / reload が失敗しないことを固定し、UI 機能追加や API 契約変更は扱わない。

## Requirements

### Requirement 1: Cross-feed pagination contract

**Objective:** As a Timeline user, I want 横断タイムラインの次ページ取得がサーバ契約どおりの baseline parameter を送る, so that 新着の追加中でも安定した pagination を継続できる

#### Acceptance Criteria

1. When cross-feed first page succeeds, the Feedman iOS app shall store response `since_time` as the current pagination baseline.
2. When cross-feed next page is requested, the Feedman iOS app shall send query item `since` with the stored `since_time` value.
3. When cross-feed next page is requested, the Feedman iOS app shall not send query item `since_time`.
4. When cross-feed next page is requested, the Feedman iOS app shall continue sending the stored cursor and normalized limit for the active pagination session.
5. If cross-feed first page has not established `since_time`, the Feedman iOS app shall not send a next-page request with a missing baseline.

### Requirement 2: Search request and response contract

**Objective:** As a Search user, I want global search to use the mobile API search contract, so that results and pagination metadata decode consistently across iOS and Android

#### Acceptance Criteria

1. When a non-empty global search query is submitted, the Feedman iOS app shall send `q` with the submitted query.
2. When a global search next page is requested, the Feedman iOS app shall send `cursor` with the stored search cursor.
3. When global search is requested, the Feedman iOS app shall send `limit` according to the existing item-list page size policy.
4. When global search is requested, the Feedman iOS app shall not send `scope`.
5. When global search succeeds, the Feedman iOS app shall decode response `items`.
6. When global search succeeds, the Feedman iOS app shall decode response `next_cursor`.
7. When global search succeeds, the Feedman iOS app shall decode response `has_more`.
8. When global search succeeds with one or more items, the Feedman iOS app shall expose decoded search items in server order.
9. When global search returns `has_more == false` or no usable `next_cursor`, the Feedman iOS app shall treat the search page as terminal.
10. Where feed-scoped search remains as an internal repository capability, the Feedman iOS app shall send `feed_id` instead of `scope=feed`.
11. The Feedman iOS app shall not expose feed-scoped search UI as part of this Issue.

### Requirement 3: Feed metadata tolerance for item list and detail

**Objective:** As a Feedman user, I want feed-scoped items and item detail to render even when redundant feed metadata is absent, so that server-valid responses do not break list or detail flows

#### Acceptance Criteria

1. When feed-scoped item list response omits `feed_title`, the Feedman iOS app shall decode the item list without treating the response as malformed.
2. When feed-scoped item list response omits `feed_favicon_url`, the Feedman iOS app shall decode the item list without treating the response as malformed.
3. When feed-scoped list UI needs a feed title for display, the Feedman iOS app shall use the selected feed metadata already held by the feed route.
4. When item detail response includes `feed_title`, the Feedman iOS app shall preserve that value for display.
5. When item detail response includes `feed_favicon_url`, the Feedman iOS app shall preserve that value for display.
6. When item detail response omits `feed_title`, the Feedman iOS app shall decode the detail without treating the response as malformed.
7. When item detail response omits `feed_favicon_url`, the Feedman iOS app shall decode the detail without treating the response as malformed.
8. When item detail lacks feed metadata and an originating summary is available, the Feedman iOS app shall prefer the originating summary metadata for display.
9. When no feed metadata is available for display, the Feedman iOS app shall render a non-crashing neutral source state rather than inventing server data.

### Requirement 4: Feed registration response and subscription refresh

**Objective:** As a Feedman user, I want feed registration success to follow the server feed response contract, so that drawer subscriptions can be refreshed from the authoritative subscription list

#### Acceptance Criteria

1. When feed registration is submitted, the Feedman iOS app shall treat server feed response fields `id`, `feed_url`, `site_url`, `title`, and `fetch_status` as the successful registration payload.
2. When feed registration succeeds with a server feed response, the Feedman iOS app shall not require subscription-only fields in the registration response.
3. When feed registration succeeds with no response body but a successful status, the Feedman iOS app shall treat the registration operation as successful.
4. When feed registration succeeds, the Feedman iOS app shall request subscription list reload before treating drawer feed rows as current.
5. When subscription list reload succeeds after registration, the Feedman iOS app shall use the reloaded subscription list as the drawer source of truth.
6. If subscription list reload fails after successful registration, the Feedman iOS app shall preserve registration success and surface a recoverable subscription refresh failure.
7. The Feedman iOS app shall not decode `POST /api/feeds` success as a subscription response shape.

### Requirement 5: Contract fixture and regression coverage

**Objective:** As a Developer, I want focused contract tests for the changed DTO and request behavior, so that future mock data cannot reintroduce the old client contract

#### Acceptance Criteria

1. When cross-feed next page request is tested, the test suite shall verify `since` is sent with the stored baseline.
2. When cross-feed next page request is tested, the test suite shall verify `since_time` is not sent as a query item.
3. When search request is tested, the test suite shall verify `scope` is not sent.
4. When search response decode is tested, the test suite shall verify wrapper response `items`, `next_cursor`, and `has_more` are decoded.
5. When feed-scoped item list decode is tested without feed metadata, the test suite shall verify decode succeeds and display metadata can be supplied from selected feed context.
6. When item detail decode is tested without feed metadata, the test suite shall verify decode succeeds and display metadata can be supplied from originating summary context.
7. When feed registration decode is tested, the test suite shall verify server feed response shape succeeds without subscription-only fields.
8. When feed registration success without body is tested, the test suite shall verify subscription reload can still be triggered.

## Non-Functional Requirements

### NFR 1: API contract compatibility

1. The Feedman iOS app shall keep RFC3339 date fields as observable strings without automatic date decoding.
2. The Feedman iOS app shall keep favicon fields nullable and shall not pass `data:` favicon URLs directly to generic remote-image loading.
3. The Feedman iOS app shall preserve existing authenticated API behavior for token refresh and auth-required error surfacing.
4. The Feedman iOS app shall not log access tokens, refresh tokens, authorization headers, search query personal data beyond debug-safe diagnostics, or response content containing personal data.

### NFR 2: Scope control

1. The implementation shall not add feed-scoped search UI.
2. The implementation shall not add keyword notification UI, OPML import/export, offline full-text cache, or feed URL editing UI.
3. The implementation shall not change server API contracts, `design/SPEC-iOS.md`, `design/SERVER.md`, or finalized specs for unrelated Issues.
4. The implementation shall not broaden into visual redesign, route redesign, or new subscription management behavior beyond the registration refresh already required here.

### NFR 3: Verification

1. When macOS and Xcode are available, the test suite shall pass `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
2. If the canonical Xcode test cannot be run in the execution environment, the implementer shall report the concrete environment limitation.

## Out of Scope

- サーバ側の API 契約文書作成、サーバ実装、または hitoshiichikawa/feedman#207 の変更。
- Feed-scoped search UI、検索履歴、検索候補のサーバ同期。
- キーワードプッシュ通知 UI、drawer 導線、`/api/devices`、`/api/keywords` 接続。
- OPML import/export、フィード URL 変更 UI、オフライン全文 cache。
- 新しい記事詳細 UI、Safari presentation、既読・スター同期方式の再設計。
- drawer / AppShell のナビゲーション再設計。
- PR 作成、commit、実装コード変更。

## Open Questions

- なし。
