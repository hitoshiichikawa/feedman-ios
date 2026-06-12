# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-12T07:30:19Z -->

## Reviewed Scope

- Branch: codex/issue-31-impl-cross-feed-repository-pagination-endpoin
- HEAD commit: 1f54fb65bb63257586915d6de60ba4d93b432cce
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `FeedRepository.loadCrossFeedFirstPage(limit:)` / `loadCrossFeedNextPage()` が追加され、real/mock repository が実装している。
- 1.2 — first page と next page が別 method として分離されている。
- 1.3 — `CrossFeedPaginationSnapshot` が items / next cursor / canLoadMore / sinceTime / limit を返す。
- 1.4 — `CrossFeedItemsResponse` と `ItemSummary` を使い、mock も API model で page を構成している。
- 1.5 — View からは `FeedRepository` 経由で、`URLSession` / Keychain / refresh 詳細は見えない。
- 2.1 — `testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime` が first page の cursor absence を検証している。
- 2.2 — 同テストが first page の `limit=50` を検証している。
- 2.3 — 同テストが first page で `since_time` を送らないことを検証している。
- 2.4 — 同テストが response の `since_time` を snapshot に保持することを検証している。
- 2.5 — `loadCrossFeedFirstPage` は `resetForRefresh()` 後に `applyFirstPage` を呼び、古い items に append しない。
- 2.6 — first page items は `CursorPaginationState.applyFirstPage` により API order のまま保持される。
- 2.7 — `CrossFeedItemsResponse.sinceTime` は non-optional `String` で、欠落や undecodable shape は `APIClient` decode error として伝播する。
- 3.1 — `testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` が stored cursor の送信を検証している。
- 3.2 — 同テストと `testInvalidLimitsAreNormalizedDeterministically` が session limit の継続を検証している。
- 3.3 — 同テストが first page 固定 `since_time` の送信を検証している。
- 3.4 — 同テストが next page items の append を検証している。
- 3.5 — 同テストが next page response の `since_time` で snapshot が上書きされないことを検証している。
- 3.6 — 同テストが異なる later page `since_time` を与えても first page 値を維持することを検証している。
- 3.7 — `testNextPageBeforeFirstPageFailsWithoutNetworkRequest` が first page 前の next page を typed error かつ no request として検証している。
- 4.1 — `testTerminalPageDoesNotRequestAnotherNextPage` が `has_more == false` の no more pages を検証している。
- 4.2 — `testNilAndEmptyNextCursorAreTerminal` が `next_cursor == nil` の terminal を検証している。
- 4.3 — 同テストが empty `next_cursor` の terminal を検証している。
- 4.4 — `testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime` が `has_more == true` かつ cursor present の canLoadMore を検証している。
- 4.5 — `testTerminalPageDoesNotRequestAnotherNextPage` が terminal 後の next page no-op と request count 維持を検証している。
- 4.6 — 同テストが terminal 後も snapshot items を維持することを検証している。
- 4.7 — `CursorPaginationState<ItemSummary>` と `CrossFeedItemsResponse: CursorPaginatedPage` を利用している。
- 5.1 — `CrossFeedPageLimit.defaultValue == 50` と first page test で default limit を検証している。
- 5.2 — `CrossFeedPageLimit.normalized` が `min(limit, 200)` を適用する。
- 5.3 — `testInvalidLimitsAreNormalizedDeterministically` が `500` を `200` に clamp することを検証している。
- 5.4 — 同テストが `0` を default `50` に正規化することを検証している。
- 5.5 — `impl-notes.md` に clamp / default 正規化方針が記載され、同テストで covered。
- 5.6 — 同テストが first page / next page とも `200` を送ることを検証している。
- 6.1 — `loadCrossFeedFirstPage` は refresh/new session として state, cursor, terminal, sinceTime を reset する。
- 6.2 — `testRefreshStartsNewSessionWithoutOldCursorOrSinceTime` が refresh request に old cursor を送らないことを検証している。
- 6.3 — 同テストが refresh request に old `since_time` を送らないことを検証している。
- 6.4 — 同テストが refreshed response の `since_time` を新 session 値として保持することを検証している。
- 6.5 — first page / refresh は request 開始時に旧 state を reset し、失敗時に partial refreshed data と previous session data を混ぜない。
- 6.6 — `APIClientFeedRepository` は actor と `isLoadingCrossFeedPage` で重複 load を deterministic error にする。
- 7.1 — `fetchCrossFeedPage` は shared `APIClient.send` で `/api/items/cross-feed` を取得している。
- 7.2 — `fetchCrossFeedPage` は `accessTokenProvider()` の token を `APIClient` の authenticated request に渡す。
- 7.3 — endpoint 固有の retry logic はなく、既存 `APIClient` refresh retry path をそのまま利用する。
- 7.4 — `testAuthRequiredErrorPropagatesWithoutEmptyTerminalState` が auth-required error propagation を検証している。
- 7.5 — `APIClientFeedRepository` は Keychain を直接参照していない。
- 7.6 — 差分内に access token / refresh token / Authorization 値の logging はない。
- 8.1 — `MockFeedRepository.defaultPages` が deterministic first page data を提供している。
- 8.2 — mock first page は non-empty cursor と `hasMore == true` を表現できる。
- 8.3 — mock second/empty page は terminal pagination を表現できる。
- 8.4 — mock は session `sinceTime` を first page response から保持する。
- 8.5 — mock next page は snapshot の fixed `sinceTime` を上書きしない。
- 8.6 — mock は `CrossFeedItemsResponse` / `ItemSummary` を使い、prototype-only field を API contract にしていない。
- 9.1 — repository は `APIClient` の typed error を catch/変換せず伝播し、transport/auth はテストされている。
- 9.2 — `testNextPageTransportErrorPropagatesAndDoesNotEndPagination` が next page error 後に terminal 化しないことを検証している。
- 9.3 — 同テストが error 後に既存 item/cursor を保持して recovery next page できることを検証している。
- 9.4 — actor と `isLoadingCrossFeedPage` により overlapping load は `loadInProgress` で拒否される。
- 9.5 — `impl-notes.md` に overlapping load の deterministic state behavior が記載されている。
- 9.6 — error path は空 item list に変換せず throw する。
- 10.1 — `testFirstPageRequestsCrossFeedWithLimitOnlyAndStoresSinceTime` が path / limit / cursor absence / sinceTime storage を検証している。
- 10.2 — 同テストが `has_more == true` と non-empty cursor の canLoadMore を検証している。
- 10.3 — `testNextPageSendsStoredCursorAndFirstPageSinceTimeThenAppendsItems` が next page query items を検証している。
- 10.4 — 同テストが append order を検証している。
- 10.5 — 同テストが first-page `since_time` 固定を検証している。
- 10.6 — `testTerminalPageDoesNotRequestAnotherNextPage` が `has_more == false` の no more pages と no extra request を検証している。
- 10.7 — `testNilAndEmptyNextCursorAreTerminal` が nil / empty cursor terminal を検証している。
- 10.8 — `testRefreshStartsNewSessionWithoutOldCursorOrSinceTime` が refresh session reset を検証している。
- 10.9 — `testInvalidLimitsAreNormalizedDeterministically` が >200 と non-positive limit の方針を検証している。
- 10.10 — `testAuthRequiredErrorPropagatesWithoutEmptyTerminalState` と `testNextPageTransportErrorPropagatesAndDoesNotEndPagination` が auth-required / transport error propagation を検証している。
- 10.11 — tests は in-memory `RecordingCrossFeedTransport` を使い、real network / OAuth / Keychain / real token に依存していない。
- 10.12 — reviewer 確認では `xcodebuild` は active developer directory が Command Line Tools のため実行不可。Core typecheck は `xcrun swiftc -typecheck ...` で成功。

## Findings

なし

## Summary

`tasks.md` と `design.md` は spec directory に存在しなかったため、boundary は `requirements.md` の実装境界と差分ファイルで確認した。差分は `Feedman/Core`、`FeedmanTests`、test target 追加、当該 spec notes に収まっており、AC 未カバー / missing test / boundary 逸脱はいずれも検出しなかった。

RESULT: approve
