# Implementation Plan

- [ ] 1. Passkey API model と repository 境界を追加する
  - `Feedman/Core/APIModels.swift` に passkey begin / finish request-response DTO、WebAuthn options subset、credential envelope、optional `UserResponse.username` を追加する。
  - `Feedman/Core/PasskeyRepository.swift` を追加し、`/api/passkey/registration/begin|finish`、`/api/passkey/authentication/begin|finish`、`/api/passkey/registration/add/begin|finish` を `APIClient` に委譲する。
  - Add begin/finish は Bearer token を渡し、401 refresh retry は既存 `APIClient` hook に委譲する。
  - Repository tests で method/path/body/header、204 no-content、error propagation、DTO encode/decode、`UserResponse.username` fallback decode を検証する。
  - _Requirements: 2.3, 2.5, 3.2, 3.4, 4.2, 4.4, 4.7, 6.6, 8.2, 8.3, 8.5, 8.6_
  - _Boundary: PasskeyAPIModels, PasskeyRepository_

- [ ] 2. AuthenticationServices platform coordinator を追加する
  - `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift` を追加し、server WebAuthn options から `ASAuthorizationPlatformPublicKeyCredentialProvider` の registration / assertion request を作る。
  - `ASAuthorizationControllerDelegate` callback を async throws に bridge し、cancellation と failure を分離する domain error を定義する。
  - Platform credential result を server finish request 用の WebAuthn-compatible credential envelope へ変換する。
  - Coordinator tests で base64url decode、required field missing、registration/assertion envelope conversion、cancellation mapping、AASA/entitlement mismatch 相当 error の failure mapping を mock で検証する。
  - _Requirements: 2.4, 2.8, 3.3, 3.7, 4.3, 4.6, 5.5, 8.1, 8.3, 8.4, 8.5, 8.6_
  - _Boundary: PasskeyPlatformAuthorizationCoordinator_
  - _Depends: 1_

- [ ] 3. LoginViewModel に passkey login / signup state machine を追加する
  - 既存 `startGoogleLogin()` と Google login URL contract を維持したまま、`startPasskeyLogin()` と `startPasskeyRegistration(username:)` を追加する。
  - Passkey login は PKCE → authentication begin → platform assertion → authentication finish → `AuthRepository.exchangeAuthCode` → `onAuthenticated` の順に実行する。
  - Passkey signup は username validation → registration begin → platform registration → registration finish → passkey authentication continuation → token exchange の順に実行する。初回 registration request に recovery email は送らない。
  - Google / passkey / signup の duplicate in-flight guard と、成功・失敗・キャンセル時の in-flight PKCE verifier / challenge cleanup を実装する。
  - ViewModel tests で signup empty username、signup success、username taken、registration cancel/failure、passkey login success、auth finish failure、token exchange failure、duplicate guard、Google regression を検証する。
  - _Requirements: 1.2, 1.5, 2.1, 2.2, 2.3, 2.5, 2.6, 2.7, 2.8, 3.1, 3.2, 3.4, 3.5, 3.6, 3.7, 6.1, 6.2, 6.7, 8.3, 8.4, 8.5, 8.6_
  - _Boundary: LoginPasskeyFlow, PasskeyAuthCodeHandoff, AuthStateIntegration_
  - _Depends: 1, 2_

- [ ] 4. Login UI に passkey 導線と signup form を追加する
  - `LoginView` / `LoginRouteView` に `PasskeyRepository` と `PasskeyPlatformAuthorizationCoordinator` dependency を渡す。
  - Google を主ボタン、パスキーでログインを副ボタン、アカウント新規作成を username-only form または sheet として表示する。
  - Recovery email input は初回登録 UI に置かない。
  - Loading / canceled / failed state を attempt kind ごとに表示し、Dynamic Type / VoiceOver label / tap target が既存 design system と整合することを確認する。
  - Lightweight UI tests または ViewModel-driven rendering checks で 3 導線表示、loading disabled、signup validation message、Google 主導線維持、accessibility label を検証する。
  - _Requirements: 1.1, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 8.1, 8.2, 8.6_
  - _Boundary: LoginPasskeyUI, LoginPasskeyFlow_
  - _Depends: 3_

- [ ] 5. Account sheet に passkey 追加登録 flow を追加する
  - `AccountViewModel` に `PasskeyEnrollmentState` と add-passkey action を追加し、current access token 必須の begin/finish flow を実装する。
  - `AccountView` に passkey add action、progress、success notice、retryable error を追加し、既存 logout と退会（アカウント削除）action を維持する。
  - Add flow の成功・失敗・キャンセルはいずれも current authenticated session と local credentials を維持する。
  - Missing token / auth-required / rate-limit / server failure を既存 Account error presentation に沿って日本語文言へ map する。
  - Account tests で add success、cancel/failure session preservation、missing token、duplicate guard、401 refresh retry delegation、delete action visibility、deletion success/failure state 不変を検証する。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 6.6, 7.1, 7.2, 7.3, 7.4, 8.2, 8.4, 8.5, 8.6_
  - _Boundary: AccountPasskeyEnrollment, PasskeyRepository, PasskeyPlatformAuthorizationCoordinator_
  - _Depends: 1, 2_

- [ ] 6. AppEnvironment wiring と Associated Domains 設定を追加する
  - `AppEnvironment` に `PasskeyRepository` dependency を追加し、production / preview / tests の injection を更新する。
  - `RootView` の unauthenticated `LoginRouteView` と authenticated `AccountRouteView` に passkey dependencies を渡す。
  - `Feedman/Feedman.entitlements` を追加し、app target Debug/Release に `CODE_SIGN_ENTITLEMENTS = Feedman/Feedman.entitlements` を設定する。
  - Entitlement には `webcredentials:$(FEEDMAN_WEBCREDENTIALS_DOMAIN)` を設定するための build configuration を追加する。値は server #216 の `WEBAUTHN_RP_ID` と同じ domain とし、具体 domain が repo 内で未確定なら値を発明せず PR 確認事項に残す。
  - `Feedman.xcodeproj/project.pbxproj` に新規 Swift files、test files、entitlements を登録する。
  - Config / project tests または shell checks で `project.pbxproj`、`Info.plist`、entitlements の plist 構文と target wiring を確認する。
  - _Requirements: 3.6, 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 8.1, 8.6_
  - _Boundary: AssociatedDomainsConfiguration, AuthStateIntegration, LoginPasskeyUI, AccountPasskeyEnrollment_
  - _Depends: 1, 2, 3, 4, 5_

- [ ] 7. Cross-boundary regression と最終検証を実行する
  - Passkey-derived account の authenticated state で Timeline / Feed / ArticleDetail が login method を知らず既存 Bearer flow を使うことを、既存 ViewModel / repository tests または smoke-level tests で確認する。
  - Google login URL / callback / token exchange regression、account deletion route preservation、logout behavior の不変性を差分レビューと tests で確認する。
  - 実ネットワーク、実 Keychain、実 Face ID / Touch ID に依存するテストを追加していないことを確認する。
  - `docs/specs/*` の本 spec 以外を implementation PR で変更していないことを差分レビューで確認する。
  - `plutil -lint`、`git diff --check`、canonical `xcodebuild ... test` を実行し、実行不能な場合は理由を PR に記載する。
  - サーバ #216 contract、production RP domain、AASA `webcredentials.apps` の確認結果または未確認事項を PR の「確認事項」に残す。
  - _Requirements: 6.3, 6.4, 6.5, 6.7, 7.1, 7.2, 7.3, 7.4, 8.5, 8.6, 8.7, 8.8_
  - _Boundary: RegressionCoverage, AuthStateIntegration, AssociatedDomainsConfiguration_
  - _Depends: 1, 2, 3, 4, 5, 6_

## Verify

本 spec の実装後、watcher（stage-a-verify gate）が再実行すべき verify コマンドを構造化ブロックで宣言する。

<!-- stage-a-verify -->
```sh
plutil -lint Feedman.xcodeproj/project.pbxproj Feedman/Info.plist Feedman/Feedman.entitlements &&
git diff --check &&
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
