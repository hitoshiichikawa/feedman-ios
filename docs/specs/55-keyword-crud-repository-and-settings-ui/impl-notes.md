# Issue #55 実装ノート

## Implementation Notes

### Task 1

- 採用方針: `/api/keywords` の API 型と repository contract を `Feedman/Core` に閉じ、UI から network/auth 詳細を隠す。
- 重要な判断: `GET /api/keywords` の response shape は未確定のため、bare array / `items` / `keywords` wrapper を repository decode 境界で吸収した。
- 残存課題: `POST` / `PATCH` が item body を返す前提は server 契約の確認が必要。

### Task 2

- 採用方針: `AppEnvironment` に `keywordRepository` を injectable dependency として追加し、production は既存 `APIClient` を共有する。
- 重要な判断: preview/test は `MockKeywordRepository` を使い、実 network / Keychain / APNs へ依存しない状態を維持した。
- 残存課題: なし。

### Task 3

- 採用方針: `KeywordSettingsViewModel` を `@MainActor` state machine として追加し、load / retry / create / edit / toggle / delete confirmation を集約した。
- 重要な判断: mutation failure は server confirmed state として表示せず、既存 visible list を保持して banner guidance に落とした。
- 残存課題: duplicate error code は固定仕様がないため、status/category/code を保守的に判定している。

### Task 4

- 採用方針: `KeywordSettingsSheet` は `FeedmanSheetShell`、`FeedmanTheme`、shared primitives を再利用して feature-local color を増やさない。
- 重要な判断: row presentation を分離し、term / enabled / hits / VoiceOver label を lightweight test で検証した。
- 残存課題: なし。

### Task 5

- 採用方針: AppShell は drawer entry、presentation state、repository/access token 注入、auth-required toast boundary のみを担当する。
- 重要な判断: `presentKeywordSettings()` は drawer を閉じつつ current route を保持し、Timeline / Feed / Search などの route state には触れない。
- 残存課題: なし。

### Task 6

- 採用方針: auth-required mutation の regression test を追加し、visible list preservation と app-level callback 呼び出しを保証した。
- 重要な判断: scope guard は `git diff --name-only develop..HEAD` と禁止語検索で確認し、今回差分は Core / Notifications / AppShell / Tests / project file / 本 spec の tasks に限定されている。
- 残存課題: なし。

### Task 7

- 採用方針: project file lint、whitespace diff、full XCTest を実行し、未確定 API 契約は確認事項として残した。
- 重要な判断: ローカル `xcode-select -p` が CommandLineTools を指していたため、Xcode 検証は `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を明示して実行した。
- 残存課題: server response shape / duplicate code の最終確認。

## Feature Flag Protocol

- `AGENTS.md` に `## Feature Flag Protocol` 節は存在しないため、opt-out として通常フローで実装した。

## 確認事項

- `GET /api/keywords` の一覧 response shape は仕様に固定されていない。実装では bare array / `items` / `keywords` wrapper を受けるが、server 契約の確定確認が必要。
- `POST /api/keywords` / `PATCH /api/keywords/{id}` は成功時に keyword item body を返す前提で実装した。no-content 成功にする場合は repository contract の追加判断が必要。
- Duplicate keyword の具体的な server error `code` は固定されていない。現状は `duplicate` / `already_exists` / status 409 などを保守的に duplicate guidance へ写像する。
- `npm test` / `npm run lint` / `npm run build` は Swift/Xcode project のため該当なし。代替として tasks.md の stage-a-verify block に従い Xcode 検証を実行した。

## Scope Guard

- `git diff --name-only develop..HEAD` は `Feedman/Core`、`Feedman/Features/Notifications`、`Feedman/Features/AppShell`、`FeedmanTests`、`Feedman.xcodeproj/project.pbxproj`、本 spec の `tasks.md` に限定されている。
- `/api/devices`、APNs token、logout unregister policy、server worker、push delivery、notification deep link、body/content matching、OPML、feed-scoped search は今回差分で追加・変更していない。
- Timeline、Feed、Starred、Search、ArticleDetail、Account、Subscription の既存 owning flow は full XCTest で regression pass を確認した。

## Verification

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: pass (`Feedman.xcodeproj/project.pbxproj: OK`)
- `git diff --check`: pass
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: pass, 437 tests, 0 failures

## AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 1.1 | `KeywordResponse` | Repository decode boundary | `KeywordRepositoryTests` decode assertions | full XCTest pass | `id` / `term` / `scope` / `enabled` / `hits` を保持 |
| 1.2 | `KeywordCreateRequest` | `KeywordSettingsViewModel.createKeyword` -> repository POST | `testCreateKeywordSendsPostBodyAndBearerToken`, `testCreateTrimsTermAndAppendsServerConfirmedKeyword` | full XCTest pass | `scope:"title"` 固定 |
| 1.3 | `KeywordUpdateRequest` | edit / toggle mutation | `testUpdateKeywordTermSendsPatchBodyAndBearerToken`, `testToggleKeywordEnabledSendsPatchBodyAndBearerToken` | full XCTest pass | mutable fields のみ encode |
| 1.4 | `APIModels.swift` keyword types | Codable model decode | `KeywordRepositoryTests` model decode | full XCTest pass | Date decode は追加なし |
| 1.5 | `KeywordSettingsRowPresentation` / sheet row | Keyword settings list rendering | `testKeywordRowPresentationIncludesTermEnabledStateAndHitsForAccessibility` | full XCTest pass | unknown scope は crash 要因にしない |
| 1.6 | `KeywordListResponse` repository boundary | `APIClientKeywordRepository.keywords` | wrapper / bare array decode tests | full XCTest pass | shape ambiguity を Core 境界で吸収 |
| 2.1 | `APIClientKeywordRepository.keywords` | sheet open / ViewModel load | `testKeywordsRequestsGetWithBearerToken` | full XCTest pass | Bearer auth |
| 2.2 | `APIClientKeywordRepository.createKeyword` | add keyword action | `testCreateKeywordSendsPostBodyAndBearerToken` | full XCTest pass | POST `/api/keywords` |
| 2.3 | `APIClientKeywordRepository.updateKeyword` | edit alert save | `testUpdateKeywordTermSendsPatchBodyAndBearerToken` | full XCTest pass | PATCH term |
| 2.4 | `APIClientKeywordRepository.updateKeyword` | enabled toggle | `testToggleKeywordEnabledSendsPatchBodyAndBearerToken` | full XCTest pass | PATCH enabled |
| 2.5 | `APIClientKeywordRepository.deleteKeyword` | delete confirmation | `testDeleteKeywordSendsDeleteWithBearerToken` | full XCTest pass | DELETE no body |
| 2.6 | `APIClient` 401 retry reuse | repository CRUD | `testKeywordOperationDelegatesExpiredTokenRefreshToAPIClient` | full XCTest pass | Notifications に refresh logic なし |
| 2.7 | typed `FeedmanAPIError` propagation | ViewModel error mapping | `testRepositoryFailurePreservesFeedmanAPIErrorContext`, guidance tests | full XCTest pass | context を握りつぶさない |
| 2.8 | repository injection | SwiftUI sheet uses repository only | `AppEnvironmentSessionRestoreTests` keyword repository wiring | full XCTest pass | View は URLSession / Keychain / APNs に触れない |
| 3.1 | `KeywordSettingsViewModel.loadKeywords` | sheet `.task` initial load | `testLoadKeywordsSuccessPreservesRepositoryOrder` | full XCTest pass | open で fetch |
| 3.2 | `contentState.loaded` | list rendering | `testLoadKeywordsSuccessPreservesRepositoryOrder` | full XCTest pass | repository order 維持 |
| 3.3 | `contentState.empty` | empty sheet state | `testLoadKeywordsEmptyShowsEmptyState` | full XCTest pass | first add affordance |
| 3.4 | `contentState.failed` / retry | recoverable error UI | `testInitialLoadFailureShowsRecoverableErrorAndRetryCanLoad` | full XCTest pass | retry action |
| 3.5 | visible list preservation | refresh / mutation after list visible | `testVisibleListRefreshFailurePreservesContentAndShowsMessage`, mutation failure tests | full XCTest pass | non-destructive guidance |
| 3.6 | `operation` guards | duplicate load/create actions | `testConcurrentLoadPreventsDuplicateRepositoryCalls`, `testConcurrentCreatePreventsDuplicateRepositoryCalls` | full XCTest pass | duplicate in-flight 抑止 |
| 3.7 | fresh ViewModel init | new sheet session | `testNewViewModelStartsWithoutStaleMessageOrConfirmation` | full XCTest pass | stale state leak なし |
| 4.1 | term validation | create / edit action | `testCreateWithWhitespaceOnlyTermDoesNotCallRepository`, `testUpdateWithWhitespaceOnlyTermDoesNotCallRepository` | full XCTest pass | create/edit 両方で whitespace-only の repository call 抑止を検証 |
| 4.2 | trim before request | create / edit action | `testCreateTrimsTermAndAppendsServerConfirmedKeyword`, `testUpdateTrimsTermAndReplacesServerConfirmedKeyword` | full XCTest pass | leading/trailing trim |
| 4.3 | duplicate error mapping | mutation failure banner | `testDuplicateRateLimitAuthAndNetworkErrorsMapToGuidance` | full XCTest pass | 登録済み guidance |
| 4.4 | rate-limit mapping | mutation failure banner | `testDuplicateRateLimitAuthAndNetworkErrorsMapToGuidance` | full XCTest pass | retry_after_seconds 表示 |
| 4.5 | transport error mapping | load / mutation failure | `testInitialLoadFailureShowsRecoverableErrorAndRetryCanLoad`, `testToggleFailurePreservesVisibleServerState` | full XCTest pass | network guidance |
| 4.6 | auth-required callback | RootView toast boundary / ViewModel handler | `testAuthRequiredCallsHandler`, `testAuthRequiredDuringVisibleMutationCallsHandlerAndPreservesContent` | full XCTest pass | RootView は toastCenter.show に接続 |
| 4.7 | delete confirmation | delete action | `testDeleteRequiresConfirmationBeforeRepositoryCall` | full XCTest pass | confirmation 前は DELETE なし |
| 4.8 | failed toggle/delete preservation | visible list mutation | `testToggleFailurePreservesVisibleServerState`, `testDeleteFailureKeepsVisibleListAndConfirmation` | full XCTest pass | failed state を confirmed 表示しない |
| 5.1 | `RootView.sheetContent(.keywordSettings)` | AppShell sheet presentation | `AppShellStateTests` keyword presentation | full XCTest pass | placeholder ではなく sheet |
| 5.2 | `KeywordSettingsSheet` / `FeedmanSheetShell` | SwiftUI `.sheet` content | compile + full XCTest | full XCTest pass | iOS 16+ compatible |
| 5.3 | sheet title/subtitle | keyword settings sheet | compile + string review | full XCTest pass | 「キーワード通知」 / title scope 説明 |
| 5.4 | row presentation | keyword list row | `testKeywordRowPresentationIncludesTermEnabledStateAndHitsForAccessibility` | full XCTest pass | term / enabled / hits |
| 5.5 | sheet controls | add/edit/toggle/delete UI actions | ViewModel mutation tests + compile | full XCTest pass | controls connected |
| 5.6 | operation progress state | sheet disabled/progress views | compile + ViewModel operation tests | full XCTest pass | affected controls disabled |
| 5.7 | `FeedmanTheme` / shared primitives | sheet rendering | compile review | full XCTest pass | hard-coded feature color 増加なし |
| 5.8 | sheet scope | keyword settings UI | scope guard search | full XCTest pass | server worker/body/feed-scoped/OPML controls なし |
| 6.1 | Drawer footer entry | AppShell drawer | compile review | full XCTest pass | existing footer action pattern |
| 6.2 | `presentKeywordSettings()` | drawer tap -> sheet | `testPresentingKeywordSettingsClosesDrawerAndPreservesCurrentRoute` | full XCTest pass | drawer dismiss |
| 6.3 | route preservation | sheet dismiss | `testPresentingKeywordSettingsClosesDrawerAndPreservesCurrentRoute` | full XCTest pass | current route preserved |
| 6.4 | auth-required toast boundary | `RootView` onAuthRequired -> `FeedmanToastCenter` | auth handler tests | full XCTest pass | silent failure なし |
| 6.5 | AppShell boundary | route state / other flows | AppShell state tests + full XCTest | full XCTest pass | existing flows unchanged |
| 7.1 | `MockKeywordRepository` | tests / previews | ViewModel tests with stubs and mock repository compile | full XCTest pass | deterministic CRUD/failure |
| 7.2 | `MockAPITransport` repository tests | real repository tests | CRUD request tests | full XCTest pass | method/path/body/Bearer |
| 7.3 | API model decode tests | Codable boundary | `KeywordRepositoryTests` decode assertions | full XCTest pass | canonical fields verified |
| 7.4 | ViewModel tests | UI state machine | `KeywordSettingsViewModelTests` | full XCTest pass | loading/success/empty/error/mutation/guard/delete |
| 7.5 | guidance tests | ViewModel error mapping | `testDuplicateRateLimitAuthAndNetworkErrorsMapToGuidance` | full XCTest pass | raw token/private data なし |
| 7.6 | no real side effects | repository / ViewModel / AppEnvironment tests | mock transport/repository tests | full XCTest pass | real network/OAuth/Keychain/APNs 依存なし |
| 8.1 | accessibility labels | row/action labels | `testKeywordRowPresentationIncludesTermEnabledStateAndHitsForAccessibility` | full XCTest pass | add/edit/toggle/delete/loading/error/retry labels implemented in sheet |
| 8.2 | wrapping layout | sheet row/input layout | compile review | full XCTest pass | fixed frames avoided, text wraps |
| 8.3 | long keyword handling | sheet row/input layout | compile review | full XCTest pass | row uses wrapping and reserved action area |
| 8.4 | no secret logging | ViewModel / sheet / AppShell | source review + auth tests | full XCTest pass | token values are not logged or displayed |
| 8.5 | boundary placement | Core / Notifications paths | `git diff --name-only develop..HEAD` review | full XCTest pass | Core/API, Notifications/UI/VM |
| 8.6 | finalized specs unchanged | docs/specs scope | git diff review | full XCTest pass | other specs untouched |
| 8.7 | English identifiers | Swift files | compile review | full XCTest pass | Swift type/file names English |
| 8.8 | Xcode test execution | full test command | `xcodebuild ... test` | pass, 437 tests, 0 failures | `DEVELOPER_DIR` 指定で実行 |

## Reviewer Round 1 是正

- `Feedman/Features/Notifications/NotificationArticleNavigation.swift` と `FeedmanTests/NotificationArticleNavigationTests.swift` を develop と等価に復元し、#55 の keyword settings 追加と共存するよう `AppShellState` / `RootView` / `AppEnvironment` の notification article routing 接続を戻した。
- `Feedman/Features/Notifications/APNsDeviceRegistrationService.swift` の `UNUserNotificationCenterDelegate` 設定と notification response handler を develop と等価に復元した。
- `docs/specs/56-notification-deep-link-to-article-detail/*` を develop と等価に復元し、他 Issue spec の削除を差分から除外した。

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| boundary:NotificationDeepLinkRouting | boundary 逸脱 | #56 の notification article deep link routing code / tests / AppShell 接続を develop と等価に戻す | `fix(notifications): restore deep link routing boundary` | `NotificationArticleNavigationTests` 16 tests | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/NotificationArticleNavigationTests test`: pass, 16 tests / 0 failures | #55 の `keywordSettings` presentation は維持し、notification article marker / pending target clear 経路を復元 |
| boundary:APNsDeviceRegistrationFoundation | boundary 逸脱 | `FeedmanAppDelegate` の notification delegate 設定と response handling を develop と等価に戻す | `fix(notifications): restore deep link routing boundary` | `APNsDeviceRegistrationServiceTests`, full XCTest | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: pass, 453 tests / 0 failures | `/api/devices` repository / logout unregister policy は変更していない |
| boundary:OtherIssueSpecs | boundary 逸脱 | `docs/specs/56-notification-deep-link-to-article-detail/*` の削除を取り消す | `fix(notifications): restore deep link routing boundary` | diff review | `git diff --check`: pass | #55 の requirements/design/tasks は変更せず、#56 spec artifacts を develop 版へ復元 |

## Reviewer Round 1 Verification

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: pass (`Feedman.xcodeproj/project.pbxproj: OK`)
- `git diff --check`: pass
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/NotificationArticleNavigationTests test`: pass, 16 tests / 0 failures
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: pass, 453 tests / 0 failures

STATUS: complete

## Reviewer Round 2 / Debugger 是正

- 採用方針: production 実装の `updateKeyword(id:term:)` には trim 後 empty guard が既にあるため、AC 4.1 の edit 側 validation を ViewModel test で直接固定した。
- 実施内容: `testUpdateWithWhitespaceOnlyTermDoesNotCallRepository` を追加し、visible list がある状態で whitespace-only edit が `false` を返し、repository operation が initial load のみで止まり、`.emptyTerm` guidance と visible list preservation が維持されることを検証した。
- 残存課題: なし。

| Target requirement | Category | Required Action | Fix commit | Test/assertion | Verification result | Notes / no-change reason |
|--------------------|----------|-----------------|------------|----------------|---------------------|--------------------------|
| 4.1 | missing test | edit/update で whitespace-only term を渡した場合に repository call を抑止し、`.emptyTerm` guidance を表示するテストを追加する | `42339d7 test(keyword): cover empty edit validation` | `testUpdateWithWhitespaceOnlyTermDoesNotCallRepository` | targeted ViewModel XCTest pass, full XCTest pass | production guard は既存実装で確認済みのため、実装変更なし |
| 7.4 | missing test | ViewModel mutation validation coverage に edit whitespace-only case を追加する | `42339d7 test(keyword): cover empty edit validation` | repository operations が `[.list(accessToken: "access-1")]` のみで `.update` を含まない assertion | targeted ViewModel XCTest pass, full XCTest pass | mock repository の deterministic operation log で検証 |

## Reviewer Round 2 Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/KeywordSettingsViewModelTests test`: pass, 18 tests, 0 failures
- `plutil -lint Feedman.xcodeproj/project.pbxproj`: pass (`Feedman.xcodeproj/project.pbxproj: OK`)
- `git diff --check`: pass
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: pass, 454 tests, 0 failures

STATUS: complete
