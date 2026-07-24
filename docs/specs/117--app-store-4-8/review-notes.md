# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-07-24T09:32:55Z -->

## Reviewed Scope

- Branch: codex/issue-117-impl--app-store-4-8
- HEAD commit: 849335f89c38894c07770575ce25a570c54ab9a5
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/Features/Login/LoginView.swift:45` / Google、パスキーログイン、新規作成の presentation を追加。`LoginViewModelTests.testLoginPresentationShowsGooglePrimaryPasskeySecondaryAndSignupEntryPoints` で確認。
- 1.2 — `Feedman/Features/Login/LoginViewModel.swift:137` / 既存 Google native login flow を維持。`LoginViewModelTests.testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading`、`testStartGoogleLoginNormalizesStaleAuthQueryParameters` で確認。
- 1.3 — `Feedman/Features/Login/LoginView.swift:45` / Google primary、passkey secondary の視覚優先度を presentation で分離。`testLoginPresentationShowsGooglePrimaryPasskeySecondaryAndSignupEntryPoints` で確認。
- 1.4 — `Feedman/Features/Login/LoginView.swift:45` / 「ユーザー名とパスキーで新規作成」を表示。`testLoginPresentationShowsGooglePrimaryPasskeySecondaryAndSignupEntryPoints` で確認。
- 1.5 — `Feedman/Features/Login/LoginViewModel.swift:173` と `Feedman/Features/Login/LoginViewModel.swift:222` / loading guard と attempt status を実装。`testLoginPresentationDisablesDuplicateAttemptsAndShowsTargetLoadingState`、`testDuplicateGuardBlocksPasskeyDuringGoogleLogin` で確認。
- 1.6 — `Feedman/Features/Login/LoginView.swift:146` / ScrollView、複数行表示、accessibility label を追加。`testLoginPresentationKeepsGoogleLoginCopyAndAccessibilityLabel` で確認。
- 2.1 — `Feedman/Features/Login/LoginView.swift:45` / signup input は username のみ。`testLoginPresentationShowsGooglePrimaryPasskeySecondaryAndSignupEntryPoints` で確認。
- 2.2 — `Feedman/Features/Login/LoginViewModel.swift:222` / 空白 username は server request 前に validation error。`testPasskeyRegistrationRejectsEmptyUsernameWithoutServerRequest`、`testPasskeyRegistrationRejectsWhitespaceUsernameWithoutServerRequest` で確認。
- 2.3 — `Feedman/Core/APIModels.swift:360` と `Feedman/Core/PasskeyRepository.swift:28` / `username` と `code_challenge` の registration begin を実装。`PasskeyRepositoryTests.testBeginRegistrationPostsUsernameAndCodeChallengeOnly` で確認。
- 2.4 — `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift:118` / registration options から platform registration request を構築。`PasskeyPlatformAuthorizationCoordinatorTests.testRegistrationRequestDecodesChallengeUserIDAndKeepsRelyingPartyString` で確認。
- 2.5 — `Feedman/Core/PasskeyRepository.swift:43` / attestation credential と `challenge_id` を registration finish に送信。`PasskeyRepositoryTests.testFinishRegistrationPostsChallengeAndCredentialAndDecodesUserIDOnly` で確認。
- 2.6 — `Feedman/Features/Login/LoginViewModel.swift:222` / `{user_id}` を token とせず、created credential ID で local assertion 後に token exchange へ合流。`testPasskeyRegistrationUsesCreatedCredentialForLocalHandoffAndAuthenticates` で確認。
- 2.7 — `Feedman/Features/Login/LoginViewModel.swift:423` / username rejected/taken を入力修正可能な error に map。`testPasskeyRegistrationUsernameTakenDoesNotCreatePlatformCredential`、`testPasskeyRegistrationInvalidUsernameDoesNotCreatePlatformCredential` で確認。
- 2.8 — `Feedman/Features/Login/LoginViewModel.swift:359` / registration finish 後の cancellation/decode/timeout を result-unknown とし raw credential を保存しない。`testPasskeyRegistrationPlatformFailurePreservesUnauthenticatedState`、`testPasskeyRegistrationFinishDispatchedCancellationBecomesResultUnknown`、`testPasskeyRegistrationCancelBeforeFinishSkipsFinishAndShowsCanceled` で確認。
- 3.1 — `Feedman/Features/Login/LoginViewModel.swift:173` / passkey login 開始時に fresh PKCE を生成。`testPasskeyLoginExchangesAuthCodeAndAuthenticates` で確認。
- 3.2 — `Feedman/Core/PasskeyRepository.swift:58` / authentication begin は `code_challenge` のみ送信。`PasskeyRepositoryTests.testBeginAuthenticationPostsCodeChallengeOnly` で確認。
- 3.3 — `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift:144` / authentication options から platform assertion request を構築。`testAssertionRequestUsesOptionsAllowCredentialsForDiscoverableLogin` で確認。
- 3.4 — `Feedman/Core/PasskeyRepository.swift:67` / assertion credential と `challenge_id` を authentication finish に送信。`PasskeyRepositoryTests.testFinishAuthenticationPostsCredentialAndDecodesAuthCode` で確認。
- 3.5 — `Feedman/Features/Login/LoginViewModel.swift:399` / `auth_code` を既存 `AuthRepository.exchangeAuthCode` に渡す。`testPasskeyLoginExchangesAuthCodeAndAuthenticates` で確認。
- 3.6 — `Feedman/Features/AppShell/RootView.swift:34` / passkey success が `environment.completeLogin` に合流。`AppEnvironmentSessionRestoreTests.testRootViewWiresPasskeyDependenciesToLoginAndAccountRoutes` と `LoginViewModelTests.testPasskeyLoginExchangesAuthCodeAndAuthenticates` で確認。
- 3.7 — `Feedman/Features/Login/LoginViewModel.swift:173` / cancellation/failure では token exchange せず未ログイン状態を維持。`testPasskeyLoginCancellationDoesNotExchangeAndAllowsRetry`、`testPasskeyLoginAuthFinishFailureDoesNotExchange`、`testPasskeyLoginTokenExchangeFailureShowsFailure` で確認。
- 4.1 — `Feedman/Features/Account/AccountView.swift:185` / account sheet に passkey add action を追加。`AccountViewModelTests.testPasskeyEnrollmentPresentationKeepsDeleteActionVisibleAndDisablesDuringAdd` で確認。
- 4.2 — `Feedman/Features/Account/AccountViewModel.swift:284` と `Feedman/Core/PasskeyRepository.swift:82` / current access token で add begin を呼ぶ。`testPasskeyEnrollmentSuccessShowsNoticeAndPreservesSession`、`PasskeyRepositoryTests.testBeginAddRegistrationUsesBearerTokenAndEmptyJSONBody` で確認。
- 4.3 — `Feedman/Features/Account/AccountViewModel.swift:284` / add begin response から platform registration request を実行。`testPasskeyEnrollmentSuccessShowsNoticeAndPreservesSession` で確認。
- 4.4 — `Feedman/Core/PasskeyRepository.swift:92` / Bearer token 付き add finish を実装。`PasskeyRepositoryTests.testFinishAddRegistrationUsesBearerTokenAndAcceptsNoContent` で確認。
- 4.5 — `Feedman/Features/Account/AccountViewModel.swift:324` / add finish success で完了 notice を表示し session を維持。`testPasskeyEnrollmentSuccessShowsNoticeAndPreservesSession` で確認。
- 4.6 — `Feedman/Features/Account/AccountViewModel.swift:284` / cancel/failure/resultUnknown で session と token を維持。`testPasskeyEnrollmentCancellationBeforeFinishSkipsFinishAndPreservesSession`、`testPasskeyEnrollmentFinishCancellationIsResultUnknownAndPreservesSession`、`testPasskeyEnrollmentFinishDecodeFailureIsResultUnknown` で確認。
- 4.7 — `Feedman/Core/PasskeyRepository.swift:82` / add endpoint は APIClient の refresh retry hook に委譲。`PasskeyRepositoryTests.testAddRegistrationDelegatesExpiredTokenRefreshToAPIClient` で確認。
- 5.1 — `Feedman/Feedman.entitlements` と `Feedman.xcodeproj/project.pbxproj:868` / Associated Domains entitlement を target に設定。`AppEnvironmentSessionRestoreTests.testAssociatedDomainsEntitlementUsesUninventedWebCredentialsBuildSetting` と `plutil` で確認。
- 5.2 — `Feedman/Feedman.entitlements` / `webcredentials:$(FEEDMAN_WEBCREDENTIALS_DOMAIN)` を設定。`testAssociatedDomainsEntitlementUsesUninventedWebCredentialsBuildSetting` で確認。
- 5.3 — `Feedman.xcodeproj/project.pbxproj:881` / bundle id は `com.hitoshiichikawa.feedman`。Team ID / AASA は repo 外の release 確認事項として `impl-notes.md` に記録。
- 5.4 — `Feedman.xcodeproj/project.pbxproj:872` / local/test build の domain は空設定で、値を発明していない。`testAssociatedDomainsEntitlementUsesUninventedWebCredentialsBuildSetting` で確認。
- 5.5 — `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift:351` / platform authorization failure を domain error 化し、Login/Account 側で credential を保存しない。`testPlatformCancellationMapsSeparatelyFromFailure` と Login/Account failure tests で確認。
- 6.1 — `Feedman/Core/AppEnvironment.swift:285` と `Feedman/Features/Login/LoginViewModel.swift:399` / passkey 成功後の token 保存は既存 AuthRepository/TokenStore 境界。`AppEnvironmentSessionRestoreTests.testProductionEnvironmentProvidesRealPasskeyRepositoryForAuthStateIntegration` で確認。
- 6.2 — `Feedman/Core/AppEnvironment.swift:130` / in-memory access token は既存 `completeLogin` に渡す。`testCompleteLoginStillTransitionsToAuthenticated` で確認。
- 6.3 — `FeedmanTests/CrossFeedRepositoryTests.swift:171` / passkey-derived token で cross-feed timeline Bearer request を確認。
- 6.4 — `FeedmanTests/CrossFeedRepositoryTests.swift:171` / passkey-derived token で feed item Bearer request を確認。
- 6.5 — `FeedmanTests/ArticleDetailViewModelTests.swift:106` / article detail と original article presentation を passkey-derived token で確認。
- 6.6 — `Feedman/Core/APIModels.swift:330` と `Feedman/Features/Account/AccountViewModel.swift:4` / `username` optional decode と表示 fallback。`PasskeyRepositoryTests.testUserResponseDecodesOptionalUsername`、`AccountViewModelTests.testDisplayUserPrefersNameThenUsernameThenEmailThenFallback` で確認。
- 6.7 — `Feedman/Features/Login/LoginViewModel.swift:137` / Google login URL と OAuth contract を維持。`LoginViewModelTests.testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` で確認。
- 7.1 — `Feedman/Features/Account/AccountView.swift:217` / delete account action を表示維持。`AccountViewModelTests.testPasskeyEnrollmentPresentationKeepsDeleteActionVisibleAndDisablesDuringAdd` で確認。
- 7.2 — `Feedman/Features/Account/AccountViewModel.swift:221` / delete confirmation flow を維持。`AccountViewModelTests.testDeleteAccountFlowIsUnchangedAfterPasskeySupport` で確認。
- 7.3 — `Feedman/Features/Account/AccountViewModel.swift:254` / deletion success path と session completion を維持。`testConfirmDeleteAccountSuccessRequestsDeleteAndCompletesSession` で確認。
- 7.4 — `Feedman/Features/Account/AccountViewModel.swift:254` / deletion failure path で session を維持。`testConfirmDeleteAccountFailurePreservesSessionAndShowsError`、`testConfirmDeleteAccountAuthRequiredPreservesLoadedUserAndDoesNotCompleteSession` で確認。
- 8.1 — `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift:1` / iOS 16+ compatible AuthenticationServices、SwiftUI、async/await、MVVM/Repository 構成で実装。full `xcodebuild` 成功記録を `impl-notes.md` で確認。
- 8.2 — `Feedman/Core/PasskeyRepository.swift:1` と Login/Account ViewModel injection / View から direct `URLSession`/Keychain access を追加していない。`PasskeyRepositoryTests` と diff review で確認。
- 8.3 — `Feedman/Core/APIModels.swift:525` / credential envelope は request DTO 境界に閉じ、token/code_verifier/raw credential の logging/persistence を追加していない。`PasskeyRepositoryTests.testCredentialEnvelopePreservesBase64URLFields` と `impl-notes.md` の grep review で確認。
- 8.4 — `Feedman/Features/Login/LoginViewModel.swift:173` と `Feedman/Features/Account/AccountViewModel.swift:284` / cancellation を validation/server failure と別状態に map。Login/Account cancellation tests で確認。
- 8.5 — `FeedmanTests/PasskeyRepositoryTests.swift:7`、`FeedmanTests/PasskeyPlatformAuthorizationCoordinatorTests.swift:7`、Login/Account ViewModel tests / mock repository・mock coordinator・mock transport の XCTest で確認。
- 8.6 — `FeedmanTests/LoginViewModelTests.swift:155`、`FeedmanTests/AccountViewModelTests.swift:175`、`FeedmanTests/CrossFeedRepositoryTests.swift:171`、`FeedmanTests/ArticleDetailViewModelTests.swift:106` / 要求された passkey success/failure、duplicate guard、Google、account deletion regression coverage を確認。
- 8.7 — `impl-notes.md` / canonical `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` が 556 tests で成功した記録を確認。Reviewer でも `plutil -lint` と `git diff --check develop..HEAD` を再実行して成功。
- 8.8 — `git diff --name-status develop..HEAD` / `docs/specs/*` の変更は `docs/specs/117--app-store-4-8` のみ。
- 8.9 — `Feedman/Features/Login/LoginViewModel.swift:42` / passkey flow は no-op event recorder 境界のみで広告目的収集を追加していない。`LoginViewModelTests.testPasskeyFlowDoesNotRecordAdvertisingInteractionEvents` で確認。
- `boundary:PasskeyAPIModels,PasskeyRepository,PasskeyPlatformAuthorizationCoordinator,LoginPasskeyFlow,PasskeyAuthCodeHandoff,AuthStateIntegration,LoginPasskeyUI,AccountPasskeyEnrollment,AssociatedDomainsConfiguration,RegressionCoverage` — `git diff --name-status develop..HEAD` の変更ファイルは tasks.md の `_Boundary:_` アノテーションに対応する Core/Login/Account/AppEnvironment/Root/project config/tests と本 spec directory に収まっている。

## Findings

なし

## Summary

全 numeric AC について、実装または対応 XCTest / 検証記録との紐付けを確認した。AC 未カバー、missing test、boundary 逸脱はいずれも確認されなかった。

RESULT: approve
