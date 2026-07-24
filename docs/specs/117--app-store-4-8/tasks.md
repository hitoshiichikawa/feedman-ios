# Implementation Plan

- [x] 1. Passkey API model と repository 境界を追加する
  - 実装着手前に `hitoshiichikawa/feedman#216` が完了し、サーバ実装が `develop` に merge 済みであることを確認する。#217 の設計 PR merge だけでは依存を満たさないため、#216 未完了なら Developer フェーズを停止して確認事項へ戻す。
  - `Feedman/Core/APIModels.swift` に distinct な registration/authentication/add begin response DTO、go-webauthn の `options.publicKey` wrapper、finish request-response DTO、credential envelope、optional `UserResponse.username` を追加する。
  - `Feedman/Core/PasskeyRepository.swift` を追加し、`/api/passkey/registration/begin|finish`、`/api/passkey/authentication/begin|finish`、`/api/passkey/registration/add/begin|finish` を `APIClient` に委譲する。
  - `PasskeyRegistrationFinishResponse` はサーバ確定契約どおり `userID` のみを decode し、`authentication/begin` request は `{code_challenge}` のみを encode する。`credential_id` などの未知 field を送らない request body test を追加する。
  - `PasskeyCredentialEnvelope` は top-level `id` / `rawId` / `type` と、registration / assertion 両方の `response.clientDataJSON` を含む完全な WebAuthn JSON schema として表現し、binary field の base64url 変換をテストする。
  - Add begin/finish は Bearer token を渡し、401 refresh retry は既存 `APIClient` hook に委譲する。
  - Repository tests で method/path/body/header、204 no-content、error propagation、distinct DTO encode/decode、`registration/finish` `{user_id}` decode、`options.publicKey` missing decode failure、`UserResponse.username` fallback decode を検証する。
  - _Requirements: 2.3, 2.5, 3.2, 3.4, 4.2, 4.4, 4.7, 6.6, 8.2, 8.3, 8.5, 8.6_
  - _Boundary: PasskeyAPIModels, PasskeyRepository_

- [x] 2. AuthenticationServices platform coordinator を追加する
  - `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift` を追加し、server WebAuthn options から `ASAuthorizationPlatformPublicKeyCredentialProvider` の registration / assertion request を作る。
  - `challenge` / `user.id` / credential descriptor ID だけを base64url decode し、`rp.id` / `rpId` は relying party domain string として provider に渡す。
  - `excludeCredentials` は platform request に適用可能な OS で best-effort に反映し、iOS 16〜17.3 では duplicate prevention を保証できない degraded behavior として扱う。server-side duplicate rejection は前提にしない。
  - Signup handoff の assertion は platform registration credential envelope から得た作成直後 credential ID を `ASAuthorizationPlatformPublicKeyCredentialAssertionRequest` の `allowCredentials` 相当にローカル適用し、通常 login の discoverable flow と分離する。
  - `ASAuthorizationControllerDelegate` callback と `ASAuthorizationControllerPresentationContextProviding` を async throws に bridge し、presentation anchor unavailable、cancellation、failure を分離する domain error を定義する。
  - Coordinator を `@MainActor` に隔離し、active attempt object が attempt 中の `ASAuthorizationController`、delegate bridge、presentation provider bridge を強参照する。完了・失敗時は continuation を exactly-once で resume してから active attempt を release し、weak delegate/provider の deallocation による callback lost を防ぐ。
  - `withTaskCancellationHandler` で active `ASAuthorizationController.cancel()` を呼ぶ。明示 cancel / Task cancellation 後も delegate callback まで active attempt を保持するか、deinit など callback を待てない経路では continuation を `.canceled` で exactly-once resume してから release する。
  - Platform credential result を server finish request 用の WebAuthn-compatible credential envelope へ変換し、registration / assertion とも top-level `id` / `rawId` / `type` / `response.clientDataJSON` を欠落させない。
  - Coordinator tests で base64url decode 対象限定、`rp.id` 非 decode、required field missing、registration/assertion envelope conversion、created credential ID extraction、local `allowCredentials` override、presentation anchor unavailable、attempt 中の controller/bridge/provider lifetime、cancel callback までの retention、continuation exactly-once、completion/cancel 後の release、`cancel()` propagation、cancellation mapping、AASA/entitlement mismatch、exclude best-effort、iOS 16〜17.3 degraded behavior を mock で検証する。
  - _Requirements: 2.4, 2.6, 2.8, 3.3, 3.7, 4.3, 4.6, 5.5, 8.1, 8.3, 8.4, 8.5, 8.6_
  - _Boundary: PasskeyPlatformAuthorizationCoordinator_
  - _Depends: 1_

- [x] 3. LoginViewModel に passkey login / signup state machine を追加する
  - 既存 `startGoogleLogin()` と Google login URL contract を維持したまま、`startPasskeyLogin()` と `startPasskeyRegistration(username:)` を追加する。
  - Passkey login は PKCE → authentication begin → platform assertion → authentication finish → `AuthRepository.exchangeAuthCode` → `onAuthenticated` の順に実行する。
  - Passkey signup は username validation → registration begin → platform registration → registration finish `{user_id}` → authentication begin `{code_challenge}` → 作成直後 credential ID でローカル制限した platform assertion → authentication finish `{auth_code}` → token exchange の順に実行する。初回 registration request に recovery email は送らず、`authentication/begin` に `credential_id` も送らない。
  - Platform credential 作成後の finish timeout / decode failure は result-unknown とし、raw credential を保存せず未ログイン状態で再試行または passkey login へ戻せる error を表示する。`registration/finish` dispatch 前 cancellation は canceled、dispatch 後 cancellation / timeout / decode failure は result-unknown として区別する。
  - Google / passkey / signup の duplicate in-flight guard と、成功・失敗・キャンセル時の in-flight PKCE verifier / challenge cleanup を実装する。Platform callback 後の race に備え、registration finish、authentication finish、token exchange の直前に attempt ID と cancellation を確認する。Finish dispatch 済み marker と token exchange dispatch 済み marker を attempt-local に保持し、server side mutation と token storage の有無を誤判定しない。
  - LoginViewModel または Login route が active signup/login `Task` を所有し、View disappearance / signup sheet dismissal 時に `Task.cancel()` と `PasskeyPlatformAuthorizationCoordinating.cancelActiveAuthorization()` を呼ぶ境界を追加する。Dismissal 後は token exchange dispatch 前の未送信 registration finish / authentication finish / token exchange へ進まないことを state machine の invariant にする。
  - `AuthRepository.exchangeAuthCode` dispatch 後は token exchange → `AppEnvironment.completeLogin` を non-cancelable auth critical section とし、dismissal cancellation があっても exchange success なら authenticated route へ遷移する。Exchange failure だけは既存 login failure と同じ failed state にする。
  - ViewModel tests で signup empty username、signup whitespace-only username、いずれも server request 数 0 で validation error になること、`INVALID_USERNAME`、username taken、signup local credential-bound success、作成直後 credential ID 欠落、registration cancel/failure/result-unknown、registration finish dispatch 前 cancellation は canceled、dispatch 後 cancellation / timeout / decode failure は result-unknown、View disappearance / signup sheet dismissal cancel 後に token exchange dispatch 前の未送信 finish/token exchange が呼ばれないこと、token exchange dispatch 後の cancellation では exchange success から `completeLogin` まで進むこと、通常 passkey login success、passkey login cancellation state、auth finish failure、token exchange failure、duplicate guard、Google regression、passkey flow が広告目的 event を出さないことを検証する。
  - _Requirements: 1.2, 1.5, 2.1, 2.2, 2.3, 2.5, 2.6, 2.7, 2.8, 3.1, 3.2, 3.4, 3.5, 3.6, 3.7, 6.1, 6.2, 6.7, 8.3, 8.4, 8.5, 8.6, 8.9_
  - _Boundary: LoginPasskeyFlow, PasskeyAuthCodeHandoff, AuthStateIntegration_
  - _Depends: 1, 2_

- [x] 4. Login UI に passkey 導線と signup form を追加する
  - `LoginView` / `LoginRouteView` に `PasskeyRepository` と `PasskeyPlatformAuthorizationCoordinator` dependency を渡す。
  - Google を主ボタン、パスキーでログインを副ボタン、アカウント新規作成を username-only form または sheet として表示する。
  - Recovery email input は初回登録 UI に置かない。
  - Signup を sheet で実装する場合は sheet dismissal が Login route の active signup `Task.cancel()` と coordinator cancel に接続されるようにし、inline form の場合も View disappearance で同じ cancel path を通す。
  - Loading / canceled / failed / resultUnknown state を attempt kind ごとに表示し、Dynamic Type / VoiceOver label / tap target が既存 design system と整合することを確認する。
  - Lightweight UI tests または ViewModel-driven rendering checks で 3 導線表示、loading disabled、signup validation message、resultUnknown の「再試行またはパスキーログインで照合」案内、Google 主導線の既存文言、ユーザー名とパスキーで新規作成すると理解できる日本語 copy、accessibility label、sheet dismissal cancellation trigger を検証する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 8.1, 8.2, 8.6_
  - _Boundary: LoginPasskeyUI, LoginPasskeyFlow_
  - _Depends: 3_

- [x] 5. Account sheet に passkey 追加登録 flow を追加する
  - `AccountViewModel` に `PasskeyEnrollmentState`（idle / adding / canceled / failed / resultUnknown / succeeded）と add-passkey action を追加し、current access token 必須の begin/finish flow を実装する。
  - `AccountView` に passkey add action、progress、success notice、retryable error、resultUnknown notice を追加し、既存 logout と退会（アカウント削除）action を維持する。
  - Add / logout / account deletion の共同 guard を実装し、add 中は logout/delete を disabled、logout/delete 進行中は add を開始しない。
  - Account sheet dismissal 時は View が所有する add ceremony `Task` を cancel し、`PasskeyPlatformAuthorizationCoordinating.cancelActiveAuthorization()` / `ASAuthorizationController.cancel()` を呼ぶ。Add finish dispatch 前 cancellation check では finish request を送らず `PasskeyEnrollmentState.canceled` を表示し、dispatch 後 cancellation / timeout / decode failure では server side mutation の有無が result-unknown であることを表示する。
  - Add flow の成功・失敗・キャンセル・result-unknown はいずれも current authenticated session と既存 token を維持し、platform credential 作成済みの可能性は server を source of truth として retry/login で照合する。
  - Missing token / auth-required / rate-limit / server failure を既存 Account error presentation に沿って日本語文言へ map する。
  - Account tests で add success notice、dedicated canceled state、dedicated resultUnknown state、add finish dispatch 前 cancellation は canceled、dispatch 後 cancellation / timeout / decode failure は result-unknown、cancel/failure/result-unknown session preservation、sheet dismissal cancel 後に未送信の add finish が呼ばれないこと、missing token、auth-required after refresh retry failure、rate-limit、server failure の各表示、duplicate guard、logout/delete 共同 guard、401 refresh retry delegation、delete action visibility、deletion success/failure state 不変、`name` → `username` → `email` precedence を検証する。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 6.6, 7.1, 7.2, 7.3, 7.4, 8.2, 8.4, 8.5, 8.6_
  - _Boundary: AccountPasskeyEnrollment, PasskeyRepository, PasskeyPlatformAuthorizationCoordinator_
  - _Depends: 1, 2_

- [x] 6. AppEnvironment wiring と Associated Domains 設定を追加する
  - `AppEnvironment` に `PasskeyRepository` dependency を追加し、production / preview / tests の injection を更新する。
  - `RootView` の unauthenticated `LoginRouteView` と authenticated `AccountRouteView` に passkey dependencies を渡す。
  - `Feedman/Feedman.entitlements` を追加し、app target Debug/Release に `CODE_SIGN_ENTITLEMENTS = Feedman/Feedman.entitlements` を設定する。
  - Entitlement には `webcredentials:$(FEEDMAN_WEBCREDENTIALS_DOMAIN)` を設定するための build configuration を追加する。値は server #216 の `WEBAUTHN_RP_ID` と同じ domain とし、具体 domain が repo 内で未確定なら値を発明せず PR 確認事項に残す。
  - `Feedman.xcodeproj/project.pbxproj` に新規 Swift files、test files、entitlements を登録する。
  - Config / project tests または shell checks で `project.pbxproj`、`Info.plist`、entitlements の plist 構文、target wiring、`AppEnvironment.production` から `completeLogin` までの injection を確認する。
  - _Requirements: 3.6, 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 8.1, 8.6_
  - _Boundary: AssociatedDomainsConfiguration, AuthStateIntegration, LoginPasskeyUI, AccountPasskeyEnrollment_
  - _Depends: 1, 2, 3, 4, 5_

- [x] 7. Cross-boundary regression と最終検証を実行する
  - Passkey-derived account の authenticated state で Timeline / Feed / ArticleDetail と `SFSafariViewController` の元記事表示が login method を知らず既存 Bearer / article open flow を使うことを、既存 ViewModel / repository tests または smoke-level tests で確認する。
  - Google login URL / callback / token exchange regression、account deletion route preservation、logout behavior の不変性を差分レビューと tests で確認する。
  - 実ネットワーク、実 Keychain、実 Face ID / Touch ID に依存するテストを追加していないことを確認する。
  - `docs/specs/*` の本 spec 以外を implementation PR で変更していないことを差分レビューで確認する。
  - `plutil -lint`、`git diff --check`、canonical `xcodebuild ... test` を実行し、実行不能な場合は理由を PR に記載する。
  - サーバ #216 が完了済みであること、`registration/finish` `{user_id}` / `authentication/begin` `{code_challenge}` / `authentication/finish` `{auth_code}` contract、production RP domain、AASA `webcredentials.apps` の確認結果または未確認事項を PR の「確認事項」に残す。
  - 署名済み実機 build と有効な AASA / Associated Domains で signup、login、add passkey、記事詳細 sheet から元記事を開く flow の manual smoke を行い、実行できない場合は理由を PR に残す。
  - Mock logger、test fixtures、diff review で raw credential、`auth_code`、access token、refresh token、`code_verifier` がログ・fixture・error message に流出していないことを確認する。
  - Passkey flow が同意なしの広告目的 interaction collection を追加していないことを差分レビューまたは既存 analytics mock tests で確認する。
  - _Requirements: 5.2, 5.3, 6.3, 6.4, 6.5, 6.7, 7.1, 7.2, 7.3, 7.4, 8.5, 8.6, 8.7, 8.8, 8.9_
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
