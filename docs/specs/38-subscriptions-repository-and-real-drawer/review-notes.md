# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-12T08:07:35Z -->

## Reviewed Scope

- Branch: codex/issue-38-impl-subscriptions-repository-and-real-drawer
- HEAD commit: ad278222f83b04f1b77d11504236fdee7dab932d
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `APIClientFeedRepository.subscriptions()` が `/api/subscriptions` へ access token 付きで `GET` し、`testSubscriptionsRequestsAuthenticatedEndpointAndMapsDrawerFeeds` で path / method / Authorization header を確認。
- 1.2 — `Subscription` 配列を `Feed` へ map し、`AppShellPreviewData.drawerFeeds` や prototype mock JSON 参照は差分内にないことを確認。
- 1.3 — `Feed.id` に `subscription.feedID` を使い、`AppShellDrawerFeedViewModel.route(for:)` が `AppShellRoute.feed(id:title:)` へ渡すことを確認。
- 1.4 — `Feed.title` に `subscription.feedTitle` を使い、repository test で display title mapping を確認。
- 1.5 — drawer の `ForEach` は offset key で描画され、重複 feed id でも SwiftUI の duplicate id crash を避ける構造を維持。tap 時の route は該当 row の `feed.id` / `feed.title` から決定される。
- 2.1 — authenticated shell の `.task` で `drawerFeedViewModel.loadSubscriptions(repository:)` を実行。
- 2.2 — `AppEnvironment.production()` が `MockFeedRepository` ではなく `APIClientFeedRepository` を組み立て、login 完了時に access token store を更新。
- 2.3 — `AppShellDrawerFeedViewModel.loadSubscriptions` が reload 開始時に既存 feeds を `.loading(feeds:)` として保持。
- 2.4 — route selection は `AppShellState` 側で処理され、subscription reload は authenticated shell の `.task` と retry action に限定されていることを確認。
- 2.5 — repository / APIClient の auth-required error は View で Keychain や URLSession を触らず、drawer state の failed state へ変換される。
- 3.1 — drawer failed state が message と retry button を表示。
- 3.2 — failure は `.failed(message:feeds:)` で表現され、empty state と分離されていることを `testLoadSubscriptionsFailureSurfacesErrorAndKeepsGlobalRoutesUsable` で確認。
- 3.3 — `testLoadSubscriptionsFailureKeepsAlreadyLoadedFeeds` が失敗時の既存 feeds 保持を確認。
- 3.4 — retry button が `loadSubscriptions(repository:)` を再実行し、`testRetrySubscriptionsCallsRepositoryAgainAndUpdatesUnreadCounts` が再呼び出しを確認。
- 3.5 — retry 成功時に `.loaded` feeds と unread count が更新されることを確認。
- 3.6 — retry 失敗時も failed state は非 crash で、global route は `AppShellState.selectRoute` で引き続き操作可能。
- 4.1 — repository state の `Feed.unreadCount` が drawer row に渡り、reload 成功ごとに更新されることを確認。
- 4.2 — `DrawerFeedButton` が `unreadCount > 0` のとき unread badge を表示。
- 4.3 — `unreadCount == 0` のとき positive badge を表示しない条件を確認。
- 4.4 — `.active` は status text を表示しない。
- 4.5 — `.stopped` は `停止中` を表示。
- 4.6 — `.error` は `取得エラー` を表示。
- 4.7 — repository mapping が `errorMessage` を `.stopped(message:)` / `.error(message:)` に保持し、message 欠落時は短い既定 label を入れる。
- 5.1 — `APIClient` の refresh retry hook と subscription repository の 401 retry 経路を `testSubscriptionsRefreshesExpiredAccessTokenAndRetries` で確認。
- 5.2 — refresh retry 成功後の subscriptions result が通常 success として drawer feeds へ返ることを確認。
- 5.3 — refresh failure / retried 401 は既存 APIClient tests で `FeedmanAPIError.authRequired` として surfacing され、View は Keychain を直接扱わない。
- 5.4 — non-auth endpoint error は `APIClient` の typed `FeedmanAPIError.feedmanError` として保持され、repository は catch せず伝播する構造を確認。
- 5.5 — `APIClientFeedRepository.subscriptions()` は `/api/auth/refresh` を直接呼ばず、refresh は `APIClient` hook / `FeedmanAuthRepository` 境界に限定。
- 6.1 — drawer は `すべての新着`、`お気に入り`、`アカウント`、既存 footer actions を維持。
- 6.2 — feed row tap は `AppShellRoute.feed(id:title:)` を選択し、`AppShellState.selectRoute` で drawer を閉じる。
- 6.3 — selected feed が reload 後に absent の場合、`feedContent` が placeholder fallback を表示し crash しない。
- 6.4 — loading / empty / failed state でも global drawer routes と footer actions は feed section とは独立して操作可能。
- 6.5 — keyword notification settings / drawer entries の追加が差分にないことを確認。
- 7.1 — drawer row は `FeedmanFaviconView` に `faviconURL` を渡し、`AsyncImage(url:)` は使っていない。
- 7.2 — `FeedmanFaviconView` / `FaviconDataURLDecoder` が null / invalid / unsupported を fallback avatar に倒す既存挙動を維持。
- 7.3 — favicon / fallback は同じ fixed frame size で row dimensions を安定させている。
- 7.4 — `Feed.faviconURL` の最小 field 追加のみで、prototype-only favicon fields は追加されていない。

## Findings

なし

## Summary

numeric AC に対応する実装とテストを確認し、AC 未カバー / missing test / boundary 逸脱に該当する reject 要因は検出しませんでした。`tasks.md` と `design.md` は spec dir に存在しなかったため、tasks の `_Boundary:_` アノテーションは確認不能でしたが、差分は提示された edit paths と requirements の実装境界内に収まっています。

RESULT: approve

---

<!-- idd-claude:review round=2 model=claude-fable-5 timestamp=2026-06-12T08:18:27Z -->

## Round 2 (macOS / Xcode 実機検証 / #22 統合)

### Findings (round 1 からの差分)

1. **#22 (PR #79) との統合**: 本ブランチ作成後に launch session 復元が develop へ merge されたため、`AppEnvironment.production()` の引数 conflict を統合 (`authenticationState: .restoring` + `accessTokenStore:` の両立)。さらにテキストマージで捕捉できない 2 点を修正:
   - `restoreSessionAtLaunch()` の成功パスで `accessTokenStore.update(...)` が呼ばれず、復元セッションで data repository が `missingAccessToken` になる統合バグ → 成功/失敗の全分岐で store を更新。
   - `AppAuthenticationState.accessToken` (本ブランチ追加の private extension) の switch に `.restoring` ケースがなく非網羅 → `.restoring → nil` を追加。
2. **autoclosure 内 await のコンパイルエラー 2 箇所** (`AppShellDrawerFeedStateTests` / `CrossFeedRepositoryTests` の actor 化 mock 参照) → 値を事前束縛へ書き換え (検証観点不変)。

### 検証結果

- 統合後の `xcodebuild test`: **TEST SUCCEEDED** (166 tests, 0 failures)

### 設計所見 (追補)

- 本 PR により #23 の `accessTokenRefreshHook` と #31 の `APIClientFeedRepository` が `production()` で実結線され、認証付きデータ取得の縦が通った。#22 で deferred とした hook 結線はここで完了。

RESULT: approve
