# Issue #56 実装メモ

## 確認事項

- 通知 payload で `data.deep_link` と `data.item_id` が両方存在し不一致の場合の最終仕様は未記載である。要件では安全側として navigation を拒否する前提にしているが、サーバー側で不一致を発生させない契約にするか確認が必要である。
- 未認証状態で通知タップ後に login した場合、同一 app session 内の pending target を自動で開くか、login 後は通常 timeline に戻すかは Issue 本文に明記がない。要件では通知意図を維持するため同一 session で開く前提にしている。

## Implementation Notes

- `Feedman/Features/Notifications/NotificationArticleNavigation.swift` を追加し、`data.deep_link` / `data.item_id` から記事 target を解決する parser と、AppDelegate から AppEnvironment へ payload を渡す bridge を分離した。
- cold launch で environment 準備前に通知応答が届く race を避けるため、bridge は handler configure 前の payload を memory queue し、configure 後に drain する。
- `AppEnvironment` は pending notification article target と non-fatal navigation error を保持するだけにし、記事 detail fetch は既存の `ArticleDetailSheet` / `ArticleDetailViewModel` に委譲した。
- `RootView` は authenticated shell に入った時だけ pending target を `AppShellState.presentNotificationArticleTarget` へ渡す。restoring / unauthenticated では authenticated content を表示しない。
- 通知起点 sheet の dismiss 時に pending target を clear し、次回 activation で同じ target が再オープンされないようにした。
- Keyword CRUD UI、notification category action、server payload contract、drawer route、独自 article detail UI は追加していない。

## Verification

- Red 確認: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/NotificationArticleNavigationTests test` は active developer directory が CommandLineTools のため失敗。
- 環境修正再試行: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を指定して同一対象テストを再実行し、15 tests / 0 failures。
- 全体検証: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は 420 tests / 0 failures。
- `npm test` / `npm run lint` / `npm run build` は iOS Xcode project のため該当なし。build は上記 `xcodebuild ... test` 内で実行済み。

## AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 1.1 | `NotificationArticleTargetParser.resolve` | `UNUserNotificationCenterDelegate.didReceive` -> `NotificationArticleNavigationBridge` -> `AppEnvironment.handleNotificationPayload` | `testValidDeepLinkExtractsArticleTarget` | `xcodebuild ... test`: 420 tests / 0 failures | `feedman://items/{id}` を target 化 |
| 1.2 | `NotificationArticleTargetParser.resolve` | 同上 | `testItemIDFallbackCreatesArticleTargetWhenDeepLinkIsAbsent` | 同上 | `data.item_id` fallback |
| 1.3 | `NotificationArticleTargetParser.itemID(fromDeepLink:)` | 同上 | `testUnsupportedSchemeRejectsNavigation`, `testUnsupportedPathRejectsNavigation` | 同上 | external URL / unsupported route を拒否 |
| 1.4 | `NotificationArticleTargetParser.resolve` | 同上 | `testEmptyDeepLinkItemIDRejectsNavigation`, `testEmptyFallbackItemIDRejectsNavigation` | 同上 | whitespace-only id を拒否 |
| 1.5 | `NotificationArticleTargetParser.resolve` | 同上 | `testConflictingDeepLinkAndItemIDRejectsNavigation` | 同上 | 不一致時は navigation しない |
| 1.6 | `AppEnvironment.handleNotificationPayload` | notification response payload handling | `testConflictingNotificationPayloadPublishesNonFatalErrorWithoutPendingTarget` | 同上 | `notificationNavigationError` に non-fatal state を保持 |
| 2.1 | `NotificationArticleNavigationBridge`, `AppEnvironment.pendingNotificationArticleTarget`, `RootView.presentPendingNotificationArticleIfPossible` | cold launch notification response -> session restore -> authenticated shell | `testBridgeQueuesColdLaunchPayloadUntilEnvironmentConfigured`, `testColdLaunchRetainsPendingArticleTargetDuringSessionRestoreAndConsumesAfterPresentation` | 同上 | presentation 自体は SwiftUI runtime 経路で既存 sheet を使用 |
| 2.2 | `RootView.body`, `AppEnvironment.pendingNotificationArticleTarget` | restoring state view | `testColdLaunchRetainsPendingArticleTargetDuringSessionRestoreAndConsumesAfterPresentation` | 同上 | restoring 中は pending 保持のみで authenticated shell を出さない |
| 2.3 | `AppEnvironment.handleNotificationPayload`, `RootView.presentPendingNotificationArticleIfPossible` | authenticated app notification response | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer` | 同上 | background/foreground tap は delegate から同じ bridge 経路 |
| 2.4 | `AppShellState.presentNotificationArticleTarget` | app shell sheet presentation | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer` | 同上 | drawer を閉じ、`.articleDetail(ArticleDetailSheetInput)` を使う |
| 2.5 | `RootView` article detail `onDismiss`, `AppShellState.dismissPresentation` | article detail sheet dismiss action | `testDismissingNotificationLaunchedDetailClearsPresentationMarker`, `testColdLaunchRetainsPendingArticleTargetDuringSessionRestoreAndConsumesAfterPresentation` | 同上 | dismiss で marker / pending を clear |
| 3.1 | `ArticleDetailSheet` existing access token injection via `RootView.sheetContent` | authenticated article detail sheet | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer`, existing `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` | 同上 | current authenticated `environment.currentAccessToken` を既存 flow に渡す |
| 3.2 | `RootView.presentPendingNotificationArticleIfPossible` guard | unauthenticated app state | `testUnauthenticatedNotificationTargetIsDeferredUntilLoginCompletes` | 同上 | unauthenticated では sheet を出さず fetch しない |
| 3.3 | `RootView.body`, `AppEnvironment.restoreSessionAtLaunch` existing failure handling | session restoration failure -> login state | existing `AppEnvironmentSessionRestoreTests.testRestoreWithoutStoredTokenShowsLoginWithoutClearing`, `testRestoreWithRejectedRefreshClearsCredentialsAndShowsLogin` | 同上 | pending target は表示されず login state のまま |
| 3.4 | `AppEnvironment.completeLogin`, `RootView` onChange authentication state | login completion in same app session | `testUnauthenticatedNotificationTargetIsDeferredUntilLoginCompletes` | 同上 | login 後も pending target を保持し shell 側が開ける |
| 3.5 | `ArticleDetailViewModel.applyFailure` existing auth-required handling | detail fetch inside existing article detail sheet | existing `ArticleDetailViewModelTests.testOpenOriginalAuthRequiredFailureRoutesAuthBoundary`, auth-required tests in detail flow | 同上 | protected content bypass は追加していない |
| 4.1 | `AppShellState.presentNotificationArticleTarget` -> `ArticleDetailSheetInput(id:)` -> existing `ArticleDetailViewModel.open` | notification-launched article detail sheet | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer`, existing `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` | 同上 | full detail fetch は既存 ViewModel |
| 4.2 | existing `ArticleDetailViewModel.loadDetail` / `ArticleDetailSheet` | article detail loading surface | existing `ArticleDetailViewModelTests.testOpenShowsSummaryLoadingWhileDetailRequestIsInFlight` | 同上 | loading state は既存表示 |
| 4.3 | existing `ArticleDetailViewModel.applyDetail` / `ArticleDetailPresentation` | article detail loaded surface | existing `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` | 同上 | loaded detail を source of truth とする |
| 4.4 | existing `ArticleDetailViewModel.applyFailure` / `ArticleDetailSheet` | recoverable detail error view | existing `ArticleDetailViewModelTests.testDetailFailureShowsRecoverableStateAndRetryUsesSameItem` | 同上 | retry affordance は既存 `FeedmanRecoverableErrorView` |
| 4.5 | existing `ArticleDetailViewModel.retry` | retry button action | existing `ArticleDetailViewModelTests.testDetailFailureShowsRecoverableStateAndRetryUsesSameItem` | 同上 | same item id で retry |
| 4.6 | existing `ArticleDetailViewModel.applyFailure` / sheet dismiss | detail error / sheet dismiss | existing `ArticleDetailViewModelTests.testDetailFailureShowsRecoverableStateAndRetryUsesSameItem`, `testDismissingNotificationLaunchedDetailClearsPresentationMarker` | 同上 | not found / inaccessible は recoverable non-auth failure として dismiss 可能 |
| 5.1 | No keyword CRUD files/routes changed | N/A (scope boundary) | diff review, full test | 同上 | keyword CRUD UI 追加なし |
| 5.2 | No notification category actions added | N/A (scope boundary) | diff review, full test | 同上 | category action button 追加なし |
| 5.3 | No server / API contract files changed | N/A (scope boundary) | diff review | 同上 | server push worker / payload contract 変更なし |
| 5.4 | Drawer routes unchanged | drawer rendering | existing drawer tests + diff review | 同上 | keyword notification settings drawer 追加なし |
| 5.5 | `AppShellPresentation.articleDetail` reused | app shell sheet presentation | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer` | 同上 | separate article detail UI 追加なし |
| NFR 1.1 | `NotificationArticleTargetParser` tests | parser unit boundary | parser tests for valid, invalid scheme/path, empty id, fallback, conflict | 同上 | required parsing coverage を追加 |
| NFR 1.2 | `AppEnvironment`, `AppShellState`, bridge tests | routing state boundary | cold-launch retention, authenticated presentation, unauthenticated deferral, dismiss clear tests | 同上 | required routing coverage を追加 |
| NFR 1.3 | `NotificationArticleTargetParser.resolve` | notification payload handling | `testMissingMalformedAndDuplicatedPayloadFieldsDoNotCrash` | 同上 | missing / malformed / duplicated shape で crash しない |
| NFR 1.4 | No logging added | N/A (privacy boundary) | diff review | 同上 | token / keyword / article content logging なし |
| NFR 2.1 | `RootView.sheetContent`, `AppShellState.presentNotificationArticleTarget` | app shell article detail sheet | `testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer` | 同上 | existing sheet behavior と互換 |
| NFR 2.2 | existing `ArticleDetailViewModel` / `ItemRepository` | article detail fetch / read marking | existing `ArticleDetailViewModelTests.testOpenFetchesDetailAndMarksReadWithPartialRequest` | 同上 | fetch/read marking は既存 flow に委譲 |
| NFR 2.3 | design/spec/prototype files unchanged | N/A (scope boundary) | `git diff -- design docs/specs/*/requirements.md` review | 同上 | design/SPEC, SERVER, prototype は変更なし |

STATUS: complete
