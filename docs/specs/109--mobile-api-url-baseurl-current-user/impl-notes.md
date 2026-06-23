# Implementation Notes

### Task 109

- 採用方針: 既存の MVVM + Repository 境界を維持し、設定解決・login URL 生成・account repository の contract 差分だけを補正した。
- 重要な判断: `AppEnvironment.production()` は `FEEDMAN_API_BASE_URL` / `FeedmanAPIBaseURL` を解決し、欠落・不正値・`localhost` を設定エラーとして扱う。unit test host の app bootstrap だけは Release 相当 runtime ではないため `127.0.0.1` を使う fallback を限定した。
- 重要な判断: native login URL は既存 query のうち contract と衝突する `flow` / `code_challenge` / `code_challenge_method` を置換し、診断用など無関係な query は保持する。
- 残存課題: production / staging の正式 origin、OAuth client ID、signing は本 Issue の scope 外で未確定。

## Verification

- Red: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/LoginViewModelTests -only-testing:FeedmanTests/AccountRepositoryTests -only-testing:FeedmanTests/AppEnvironmentSessionRestoreTests test` -> expected compile failure: `AppEnvironment.resolveProductionAPIBaseURL` / `AppEnvironmentConfigurationError` 未実装。
- Targeted green: same command -> 31 tests passed.
- Canonical test: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` -> 459 tests passed.
- `npm test` / `npm run lint` / `npm run build`: `package.json` が無い iOS Xcode project のため対象外。canonical `xcodebuild ... test` で build と XCTest を確認。

## 確認事項

- なし。

## AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 1.1 | `AppEnvironment.resolveProductionAPIBaseURL` / `AppEnvironment.production` | app launch `FeedmanApp` -> `AppEnvironment.production()` | `testConfiguredProductionAPIBaseURLUsesEnvironmentOrigin` | canonical test: 459 passed | 明示設定 origin を runtime 設定として使用 |
| 1.2 | `AppEnvironment.resolveProductionAPIBaseURL` | app launch configuration validation | `testConfiguredProductionAPIBaseURLRejectsMissingReleaseEquivalentOrigin` | canonical test: 459 passed | 欠落時に localhost default へ戻らない |
| 1.3 | `APIClient(baseURL:)` construction in `AppEnvironment.production` | authenticated repository requests created from production environment | `testProductionEnvironmentUsesAPIClientKeywordRepository`, `testConfiguredProductionAPIBaseURLUsesEnvironmentOrigin` | canonical test: 459 passed | APIClient 生成に同じ resolved origin を渡す |
| 1.4 | `authBaseURL: apiBaseURL` in `AppEnvironment.production` | login view receives `environment.authBaseURL` | `testProductionEnvironmentUsesConfiguredOriginForNativeLoginBase` | canonical test: 459 passed | native Google login base も同じ origin |
| 1.5 | `AppEnvironmentConfigurationError`, `fatalError` in `production()` | app launch configuration validation | `testConfiguredProductionAPIBaseURLRejectsMissingReleaseEquivalentOrigin`, `testConfiguredProductionAPIBaseURLDoesNotUseLocalhostAsImplicitReleaseDefault` | canonical test: 459 passed | app launch 1 回以内に developer-observable failure |
| 2.1 | `LoginViewModel.makeGoogleLoginURL` | user taps Google login -> `startGoogleLogin()` | `testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` | canonical test: 459 passed | `flow=native` |
| 2.2 | `LoginViewModel.makeGoogleLoginURL` | user taps Google login -> `startGoogleLogin()` | `testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` | canonical test: 459 passed | current PKCE challenge を設定 |
| 2.3 | `LoginViewModel.makeGoogleLoginURL` | user taps Google login -> `startGoogleLogin()` | `testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` | canonical test: 459 passed | `code_challenge_method=S256` |
| 2.4 | query conflict filter in `makeGoogleLoginURL` | user taps Google login with stale configured auth URL | `testStartGoogleLoginNormalizesStaleAuthQueryParameters` | canonical test: 459 passed | stale `flow=web` を `native` へ置換 |
| 2.5 | query conflict filter in `makeGoogleLoginURL` | user taps Google login with stale configured auth URL | `testStartGoogleLoginNormalizesStaleAuthQueryParameters` | canonical test: 459 passed | stale `code_challenge` を current challenge へ置換 |
| 2.6 | query conflict filter in `makeGoogleLoginURL` | user taps Google login with stale configured auth URL | `testStartGoogleLoginNormalizesStaleAuthQueryParameters` | canonical test: 459 passed | stale method を `S256` へ置換 |
| 2.7 | inherited query preservation in `makeGoogleLoginURL` | user taps Google login with diagnostic query | `testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading`, `testStartGoogleLoginNormalizesStaleAuthQueryParameters` | canonical test: 459 passed | `diagnostic=1` を保持 |
| 2.8 | no WebView path added | login flow remains `ASWebAuthenticationSession` | existing `LoginViewModelTests` session starter assertions | canonical test: 459 passed | WebView Cookie fallback は未追加 |
| 3.1 | `FeedmanAccountRepository.currentUser` | account feature `AccountViewModel.loadCurrentUser()` -> repository | `testCurrentUserRequestsUsersMeWithBearerToken` | canonical test: 459 passed | `GET /api/users/me` |
| 3.2 | `FeedmanAccountRepository.currentUser` access token argument | account feature authenticated repository boundary | `testCurrentUserRequestsUsersMeWithBearerToken`, `testCurrentUserDelegatesExpiredTokenRefreshToAPIClient` | canonical test: 459 passed | Bearer token と refresh retry を維持 |
| 3.3 | unchanged `UserResponse` decode + account success path | account view model load success | existing `AccountViewModelTests.testLoadCurrentUserShowsLoadingThenSuccess`, `testUserResponseDecodesMobileCurrentUserContractFields` | canonical test: 459 passed | response 表示 path は既存の success path |
| 3.4 | `FeedmanAccountRepository.currentUser` path change | account current user loading | `testCurrentUserRequestsUsersMeWithBearerToken` | canonical test: 459 passed | `/auth/me` は current user 取得に使わない |
| 3.5 | `FeedmanAccountRepository.deleteCurrentUser` unchanged | account deletion confirmation flow | `testDeleteCurrentUserRequestsUsersMeWithBearerToken` | canonical test: 459 passed | DELETE は `/api/users/me` のまま |
| 4.1 | `README.md` Configuration / API base URL | developer setup docs | document diff review | canonical test: 459 passed | Simulator / device testing の設定方法を追記 |
| 4.2 | `README.md` Configuration / API base URL | developer setup docs | document diff review | canonical test: 459 passed | local-development origin と Release 相当を区別 |
| 4.3 | `README.md` v1 Smoke Test Checklist | manual smoke checklist | document diff review | canonical test: 459 passed | login URL の required query を明記 |
| 4.4 | `README.md` v1 Smoke Test Checklist | manual smoke checklist | document diff review | canonical test: 459 passed | current user endpoint を明記 |
| 4.5 | `README.md` Configuration | developer setup docs | document diff review | canonical test: 459 passed | production / staging URL は未確定として値を発明しない |
| 5.1 | `LoginViewModelTests` | XCTest login URL regression | `testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` | canonical test: 459 passed | S256 regression |
| 5.2 | `LoginViewModelTests` | XCTest login URL regression | `testStartGoogleLoginNormalizesStaleAuthQueryParameters` | canonical test: 459 passed | stale query normalization regression |
| 5.3 | `AccountRepositoryTests` | XCTest repository boundary | `testCurrentUserRequestsUsersMeWithBearerToken` | canonical test: 459 passed | current user path regression |
| 5.4 | `AppEnvironmentSessionRestoreTests` | XCTest configuration resolver | `testConfiguredProductionAPIBaseURLDoesNotUseLocalhostAsImplicitReleaseDefault` | canonical test: 459 passed | Release 相当 origin が localhost 固定でないことを確認 |
| 5.5 | `xcodebuild ... test` | full XCTest suite | canonical test command | 459 tests passed | macOS/Xcode で実行済み |

STATUS: complete
