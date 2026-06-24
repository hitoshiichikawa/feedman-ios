# Design Document

## Overview

Issue #110 は、iOS client の mobile API DTO / request construction / display fallback を、サーバ側 Issue hitoshiichikawa/feedman#207 で確定した v1 mobile API contract に揃える。
設計上の主眼は、古い mock data 由来の contract drift を repository boundary で吸収し、View / ViewModel が server-valid response を malformed と扱わないようにすることである。

本 design は `design/SPEC-iOS.md` と `design/SERVER.md` を正本とし、UI 機能追加や server contract 変更は扱わない。

## Scope

- Cross-feed timeline pagination の baseline query を `since_time` から `since` へ合わせる。
- Global search request / response を mobile API contract の `q` / `cursor` / `limit` と `{ items, next_cursor, has_more }` wrapper へ合わせる。
- Feed-scoped item list / item detail の redundant feed metadata 欠落を decode error にしない。
- Feed registration success response を feed response shape または empty success body として扱い、drawer の正本は subscription reload に置く。
- 上記 contract drift を unit test fixture と request assertion で固定する。

## Components And Interfaces

### CrossFeedPaginationContract

`CrossFeedRepository` は first page response の `since_time` を pagination session の immutable baseline として保持する。
Next page request は server cursor と normalized limit に加えて、保持済み baseline を `since` query item として送る。
旧 contract の `since_time` query item は request builder から除去する。

Baseline が未確立の状態で next page が要求された場合、repository は network request を作らず、pagination state error として扱う。
これにより、server が必要とする安定 pagination baseline が欠落したまま request されることを防ぐ。

### SearchAPIContract

Global search は `q` / `cursor` / `limit` のみを query item として使う。
`scope` は送らない。
Response は root object の `items`, `next_cursor`, `has_more` を decode し、item order は server order をそのまま ViewModel へ渡す。

Terminal page 判定は `has_more == false` または usable な `next_cursor` が無い場合に true とする。
Feed-scoped search は v1 UI には出さないが、repository internal capability として残る場合は `scope=feed` ではなく `feed_id` を送る。

### ItemFeedMetadataContract

`ItemSummary` と `ItemDetail` は `feed_title` / `feed_favicon_url` を redundant metadata として扱う。
Feed-scoped list response や item detail response がこれらを省略しても decode は成功させる。

表示 metadata の優先順位は以下とする。

1. Detail response が持つ feed metadata。
2. Originating summary が持つ feed metadata。
3. Feed route が保持する selected feed metadata。
4. Neutral source state。

Client は metadata 欠落時に server data を捏造せず、空文字や nil を missing metadata として表示層で補完する。

### FeedRegistrationContract

`POST /api/feeds` success は server feed response shape の `id`, `feed_url`, `site_url`, `title`, `fetch_status` を登録 payload として decode する。
Registration response では subscription-only fields を要求しない。

Successful status かつ response body が空の場合も registration operation 自体は success とする。
登録成功後の drawer feed rows は `/api/subscriptions` reload を source of truth とし、reload 成功時は reloaded subscription list で drawer state を置き換える。
Reload failure は registration success を取り消さず、recoverable subscription refresh failure として UI に戻す。

### ContractRegressionCoverage

Regression coverage は DTO decode test、repository request assertion、ViewModel presentation fallback test に分ける。
Network token refresh や Keychain behavior は既存 contract を維持し、この Issue の test では実 network / 実 Keychain に依存しない。

## Data Contract Summary

| Area | Client input/output | Server contract | Client behavior |
|------|---------------------|-----------------|-----------------|
| Cross-feed first page | response `since_time` | pagination baseline | session に保存する |
| Cross-feed next page | query `since` | stored baseline | `since_time` query は送らない |
| Global search request | query `q`, `cursor`, `limit` | mobile search params | `scope` は送らない |
| Global search response | `items`, `next_cursor`, `has_more` | wrapper response | metadata と item order を保持する |
| Internal feed search | query `feed_id` | feed-scoped parameter | UI には出さない |
| Item list/detail | optional `feed_title`, `feed_favicon_url` | redundant metadata | decode を成功させ fallback 表示する |
| Feed registration | feed response or empty success | registered feed payload | subscription reload を drawer 正本にする |

## Traceability Matrix

| Requirement / AC | Design component | Task |
|------------------|------------------|------|
| 1.1 | CrossFeedPaginationContract | Task 1 |
| 1.2 | CrossFeedPaginationContract | Task 1 |
| 1.3 | CrossFeedPaginationContract | Task 1 |
| 1.4 | CrossFeedPaginationContract | Task 1 |
| 1.5 | CrossFeedPaginationContract | Task 1 |
| 2.1 | SearchAPIContract | Task 2 |
| 2.2 | SearchAPIContract | Task 2 |
| 2.3 | SearchAPIContract | Task 2 |
| 2.4 | SearchAPIContract | Task 2 |
| 2.5 | SearchAPIContract | Task 2 |
| 2.6 | SearchAPIContract | Task 2 |
| 2.7 | SearchAPIContract | Task 2 |
| 2.8 | SearchAPIContract | Task 2 |
| 2.9 | SearchAPIContract | Task 2 |
| 2.10 | SearchAPIContract | Task 2 |
| 2.11 | SearchAPIContract | Task 2 |
| 3.1 | ItemFeedMetadataContract | Task 3 |
| 3.2 | ItemFeedMetadataContract | Task 3 |
| 3.3 | ItemFeedMetadataContract | Task 3 |
| 3.4 | ItemFeedMetadataContract | Task 3 |
| 3.5 | ItemFeedMetadataContract | Task 3 |
| 3.6 | ItemFeedMetadataContract | Task 3 |
| 3.7 | ItemFeedMetadataContract | Task 3 |
| 3.8 | ItemFeedMetadataContract | Task 3 |
| 3.9 | ItemFeedMetadataContract | Task 3 |
| 4.1 | FeedRegistrationContract | Task 4 |
| 4.2 | FeedRegistrationContract | Task 4 |
| 4.3 | FeedRegistrationContract | Task 4 |
| 4.4 | FeedRegistrationContract | Task 4 |
| 4.5 | FeedRegistrationContract | Task 4 |
| 4.6 | FeedRegistrationContract | Task 4 |
| 4.7 | FeedRegistrationContract | Task 4 |
| 5.1 | ContractRegressionCoverage, CrossFeedPaginationContract | Task 1, Task 5 |
| 5.2 | ContractRegressionCoverage, CrossFeedPaginationContract | Task 1, Task 5 |
| 5.3 | ContractRegressionCoverage, SearchAPIContract | Task 2, Task 5 |
| 5.4 | ContractRegressionCoverage, SearchAPIContract | Task 2, Task 5 |
| 5.5 | ContractRegressionCoverage, ItemFeedMetadataContract | Task 3, Task 5 |
| 5.6 | ContractRegressionCoverage, ItemFeedMetadataContract | Task 3, Task 5 |
| 5.7 | ContractRegressionCoverage, FeedRegistrationContract | Task 4, Task 5 |
| 5.8 | ContractRegressionCoverage, FeedRegistrationContract | Task 4, Task 5 |

## Non-Functional Coverage

- RFC3339 date fields は API model の observable value として `String` のまま保持する。
- Favicon field は nullable のまま扱い、`data:` URL を generic remote-image loader に渡す経路を増やさない。
- Authenticated API behavior、token refresh、auth-required error surfacing は既存 APIClient contract を維持する。
- Secret、token、authorization header、search query personal data、personal response content の logging は追加しない。
- Feed-scoped search UI、keyword notification UI、OPML、offline full-text cache、feed URL editing UI は追加しない。

## Risks And Mitigations

| Risk | Mitigation |
|------|------------|
| 古い fixture が再び `scope` や subscription response shape を正本化する | request assertion と decode fixture を mobile API contract に合わせて固定する |
| Feed metadata 欠落時に UI が空 title をそのまま表示する | ViewModel presentation fallback test で selected feed / originating summary / neutral state を固定する |
| Empty body registration success が drawer 更新なしで成功扱いになる | success event 後の subscription reload trigger を AppShell test で固定する |
| Pagination baseline 欠落のまま next page を呼ぶ | repository test で no network request を固定する |

## Out Of Scope

- Server API contract の変更。
- `design/SPEC-iOS.md` / `design/SERVER.md` の変更。
- Feed-scoped search UI の追加。
- Keyword notification、OPML、offline cache、feed URL editing の追加。
- Visual redesign、navigation redesign、article detail presentation redesign。
