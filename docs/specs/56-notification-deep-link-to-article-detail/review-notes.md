# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-22T12:54:45Z -->

## Reviewed Scope

- Branch: codex/issue-56-impl-notification-deep-link-to-article-detail
- HEAD commit: 279caef40140e1066f34a8edece3f977545dd502
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `NotificationArticleTargetParser.resolve` と `testValidDeepLinkExtractsArticleTarget` で `feedman://items/{id}` から item id を抽出。
- 1.2 — `testItemIDFallbackCreatesArticleTargetWhenDeepLinkIsAbsent` で `data.item_id` fallback を確認。
- 1.3 — `testUnsupportedSchemeRejectsNavigation` / `testUnsupportedPathRejectsNavigation` で unsupported deep link を拒否。
- 1.4 — `testEmptyDeepLinkItemIDRejectsNavigation` / `testEmptyFallbackItemIDRejectsNavigation` で空白 item id を拒否。
- 1.5 — `testConflictingDeepLinkAndItemIDRejectsNavigation` で deep link と item_id の不一致を拒否。
- 1.6 — `AppEnvironment.handleNotificationPayload` と `testConflictingNotificationPayloadPublishesNonFatalErrorWithoutPendingTarget` で non-fatal error state を公開。
- 2.1 — `NotificationArticleNavigationBridge` と `pendingNotificationArticleTarget` により cold launch payload を environment configure 後まで保持。
- 2.2 — `RootView.body` は `.restoring` 中に authenticated shell を表示せず、pending target は `AppEnvironment` に保持。
- 2.3 — `FeedmanAppDelegate.userNotificationCenter(_:didReceive:)` から bridge 経由で authenticated shell に通知 target を渡す。
- 2.4 — `AppShellState.presentNotificationArticleTarget` と `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer` で既存 article detail sheet と drawer close を確認。
- 2.5 — `RootView.activePresentationBinding` / `ArticleDetailSheet.onDismiss` が `AppShellPresentationDismissalHandler.dismissActivePresentation` を通り、`testBindingDismissOfNotificationLaunchedDetailClearsPendingTarget` で pending target clear を確認。
- 3.1 — `RootView.sheetContent` が `environment.currentAccessToken` を既存 `ArticleDetailSheet` に渡す。
- 3.2 — `presentPendingNotificationArticleIfPossible` の authenticated guard と `testUnauthenticatedNotificationTargetIsDeferredUntilLoginCompletes` で unauthenticated fetch を抑止。
- 3.3 — 既存 `AppEnvironmentSessionRestoreTests.testRestoreWithoutStoredTokenShowsLoginWithoutClearing` / `testRestoreWithRejectedRefreshClearsCredentialsAndShowsLogin` が restore failure 後の login state を確認。
- 3.4 — `testUnauthenticatedNotificationTargetIsDeferredUntilLoginCompletes` で login 後も pending target が残ることを確認。
- 3.5 — 既存 `ArticleDetailViewModelTests.testOpenOriginalAuthRequiredFailureRoutesAuthBoundary` などの auth-required handling を再利用。
- 4.1 — `AppShellState.presentNotificationArticleTarget` が `ArticleDetailSheetInput(id:)` を既存 detail flow に渡す。
- 4.2 — 既存 `ArticleDetailViewModelTests.testOpenShowsSummaryLoadingWhileDetailRequestIsInFlight` が loading state を確認。
- 4.3 — 既存 `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` が loaded detail を source of truth として確認。
- 4.4 — 既存 `ArticleDetailViewModelTests.testDetailFailureShowsRecoverableStateAndRetryUsesSameItem` が recoverable error と retry affordance を確認。
- 4.5 — 同 test で同一 item id の retry を確認。
- 4.6 — 既存 recoverable error sheet と dismiss 可能な sheet surface を再利用。
- 5.1 — 差分に keyword CRUD UI 追加なし。
- 5.2 — 差分に notification category action button 追加なし。
- 5.3 — server-side push worker / payload contract 変更なし。
- 5.4 — drawer route 変更なし。
- 5.5 — `AppShellPresentation.articleDetail` を再利用し、別 article detail UI は追加なし。
- NFR 1.1 — parser tests が valid deep link、invalid scheme/path、empty id、fallback、conflict を確認。
- NFR 1.2 — `testBindingDismissOfNotificationLaunchedDetailClearsPendingTarget` が binding dismiss 相当経路で `AppEnvironment.pendingNotificationArticleTarget` が nil になることを確認。
- NFR 1.3 — `testMissingMalformedAndDuplicatedPayloadFieldsDoNotCrash` で malformed / duplicated shape を確認。
- NFR 1.4 — token / keyword / article content logging の追加なし。
- NFR 2.1 — `AppShellState.presentNotificationArticleTarget` が existing app shell article detail presentation を使う。
- NFR 2.2 — article detail fetch と read marking は既存 `ArticleDetailViewModel` / repository flow に委譲。
- NFR 2.3 — `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files の変更なし。

## Findings

なし

## Summary

Round 1 の AC 2.5 / NFR 1.2 指摘は `AppShellPresentationDismissalHandler` と追加テストで解消されています。`tasks.md` は指定 spec ディレクトリに存在しないため `_Boundary:_` アノテーションとの照合はできませんでしたが、差分上の scope 逸脱は見つかりませんでした。
対象テスト `NotificationArticleNavigationTests` は 16 tests / 0 failures で成功しました。

RESULT: approve
