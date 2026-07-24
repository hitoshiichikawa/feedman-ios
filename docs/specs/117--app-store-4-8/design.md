# Design Document

## Overview

本機能は Feedman iOS の認証入口にパスキーを追加し、Google OAuth のみの状態から App Store Review Guideline 4.8 に適合できる構成へ移行する。Apple の最新 Guideline 4.8 は代替 login option に「氏名・メールへの収集制限」「メール非公開」「同意なしに広告目的でアプリ内 interaction を収集しない」の三条件を求めているため、本 spec は username-only の passkey option に加えて広告目的収集を行わないことを検証対象に含める。サーバ側 #216 / PR #217 の passkey API は WebAuthn ceremony を提供し、authentication finish 成功時に既存 native auth と同じ `auth_code` を返すため、iOS 側は既存 `AuthRepository.exchangeAuthCode`、`TokenStore`、`AppEnvironment.completeLogin` を再利用する。

ログイン画面では Issue コメント回答どおり Google を主導線のまま維持し、パスキーでログインとアカウント新規作成を副導線として追加する。新規作成では初回に recovery email を収集せず username のみを送る。サーバ確定契約では `registration/finish` は `{user_id}` のみを返すため、登録完了直後のログイン済み遷移は platform registration 結果から得た作成直後 credential ID を iOS 側の assertion request `allowedCredentials` にだけ適用し、サーバには `authentication/begin` `{code_challenge}` のみを送る。空の `allowCredentials` による discoverable login を登録直後 handoff には使わず、複数 Feedman passkey が同一端末にある場合でも別アカウントへログインしない契約にする。

**Purpose**: この機能は Google に依存しないアカウント作成・ログイン手段を Feedman iOS ユーザーに提供する。
**Users**: 新規ユーザーは username + platform passkey で登録し、既存 Google ユーザーは Account sheet から自分のアカウントへ passkey を追加する。
**Impact**: 現在の Google-only login screen と Account sheet を、既存 OAuth / token / account deletion flow を壊さず passkey 対応へ拡張する。

### Goals

- Google login regression を出さず、ログイン画面に passkey login / signup 導線を追加する。
- AuthenticationServices の platform passkey ceremony を repository / coordinator 境界に閉じ、View から network / Keychain / raw credential を直接扱わせない。
- Passkey 成功後は既存 `auth_code` → token exchange → authenticated shell に合流する。
- Google 由来の既存アカウントへ passkey を追加登録できる。
- Associated Domains `webcredentials` とサーバ AASA の整合を実装タスクに落とす。
- パスキー導入が App Store Guideline 4.8 の privacy 条件を満たすことを設計・テスト・PR 確認事項で示す。

### Non-Goals

- Sign in with Apple、パスワード認証、Web フロントの passkey UI。
- サーバ #216 の endpoint 実装、AASA 配信、DB / WebAuthn 検証実装。
- Recovery email の初回収集、設定画面での recovery email 編集 endpoint 実装。
- Passkey credential の一覧、削除、リネーム、複数 credential 管理 UI。
- Account deletion flow の再設計。
- Physical security key 専用 UI。iOS platform passkey（Face ID / Touch ID など）を対象にする。

## Architecture

### Existing Architecture Analysis

- 現在の login は `LoginView` / `LoginViewModel` が PKCE challenge を生成し、`ASWebAuthenticationSession` で `/auth/google/login?flow=native...` を開き、callback URL の `auth_code` を `AuthRepository.exchangeAuthCode` へ渡す。
- `AuthRepository` は `POST /api/auth/token` と refresh token Keychain 保存の境界であり、View は Keychain や `URLSession` に触らない。
- `AppEnvironment.completeLogin` は access token の in-memory 保存、authenticated route への遷移、APNs device registration retry を担う。Passkey 成功時もこの境界へ合流する。
- `AccountView` / `AccountViewModel` は current user loading、logout、account deletion を担い、`DELETE /api/users/me` と local credential clear は既に実装済みである。Passkey add はこの Account feature に追加する。
- `APIClient` は Bearer token 付き request の 401 refresh retry hook を持つ。Account passkey add の authenticated endpoint はこの既存 hook に委譲し、Account feature 内で refresh を実装しない。
- `Feedman.xcodeproj` は明示的な project file 管理で、新規 Swift file / entitlements file は `project.pbxproj` への登録が必要になる。現状 `CODE_SIGN_ENTITLEMENTS` は未設定。

### Architecture Pattern & Boundary Map

```mermaid
flowchart TB
    LV[LoginView] --> LVM[LoginPasskeyFlow]
    LVM --> PKCE[PKCELoginChallengeGenerator existing]
    LVM --> PR[PasskeyRepository]
    LVM --> PC[PasskeyPlatformAuthorizationCoordinator]
    LVM --> AR[AuthRepository existing]
    AR --> TS[TokenStore existing]
    LVM --> AE[AuthStateIntegration / AppEnvironment]

    AV[AccountView] --> AVM[AccountPasskeyEnrollment]
    AVM --> PR
    AVM --> PC
    AVM --> API[APIClient existing refresh retry]

    CFG[AssociatedDomainsConfiguration] --> PC
    PR --> S216[Feedman API #216 passkey endpoints]
    S216 --> AASA[/.well-known/apple-app-site-association]
```

**Architecture Integration**:
- 採用パターン: MVVM + Repository + coordinator。Network は `PasskeyRepository`、platform API は `PasskeyPlatformAuthorizationCoordinator`、UI state は ViewModel に分離する。
- ドメイン／機能境界:
  - Login feature: 未認証状態の Google / passkey login / passkey signup state machine。
  - Account feature: 認証済み account sheet での passkey add state machine。
  - Core auth: API DTO、repository、platform coordinator、既存 token exchange handoff。
  - Project configuration: Associated Domains entitlement と Xcode target wiring。
- 既存パターンの維持:
  - `AuthRepository.exchangeAuthCode` を passkey でも使い、新しい token 保存経路を作らない。
  - View から `URLSession`、Keychain、AuthenticationServices delegate の raw callback を直接扱わない。
  - API 日付変換ルールに影響しない。新 DTO に日付は不要。
  - Account deletion action は表示・状態・API path を維持する。
- 新規コンポーネントの根拠:
  - `PasskeyRepository`: #216 passkey endpoint 群が既存 auth repository と異なる ceremony DTO を扱うため。
  - `PasskeyPlatformAuthorizationCoordinator`: `ASAuthorizationController` delegate/callback を async API に変換し、ViewModel tests で mock 可能にするため。
  - `PasskeyAuthCodeHandoff`: registration finish 後の local credential-bound auth continuation と authentication finish の `auth_code` 合流を 1 箇所に閉じるため。

### Technology Stack

| Layer | Choice / Version | Role in Feature | Notes |
|-------|------------------|-----------------|-------|
| Frontend / CLI | SwiftUI, iOS 16+ | Login / Account UI | Existing FeedmanTheme and sheet primitives |
| Backend / Services | Feedman API #216 passkey endpoints | WebAuthn begin/finish, AASA | Server implementation is outside this repo |
| Data / Storage | Existing Keychain TokenStore | Refresh token persistence after token exchange | No new local credential storage |
| Messaging / Events | None | Not used | Existing APNs retry after login remains |
| Infrastructure / Runtime | Xcode project, Associated Domains entitlement | `webcredentials` domain alignment | Requires Team ID / RP ID confirmation |
| Platform API | AuthenticationServices | Platform passkey registration/assertion | Official Apple docs confirm associated domains and platform credential provider flow |

## File Structure Plan

### Directory Structure

```
Feedman/
├── Core/
│   ├── APIModels.swift                         # PasskeyAPIModels: passkey request/response DTO と WebAuthn publicKey wrapper を追加
│   ├── PasskeyRepository.swift                 # PasskeyRepository: #216 endpoint wrapper と mock
│   └── Auth/
│       ├── AuthRepository.swift                # AuthStateIntegration: 既存 exchangeAuthCode を維持
│       └── PKCE.swift                          # 既存 PKCE utility を再利用
├── Features/
│   ├── Login/
│   │   ├── LoginViewModel.swift                # LoginPasskeyFlow / PasskeyAuthCodeHandoff: passkey state machine と auth_code 合流
│   │   ├── LoginView.swift                     # LoginPasskeyUI: Google 主導線 + passkey 導線 + signup form
│   │   └── PasskeyPlatformAuthorizationCoordinator.swift
│   │                                           # PasskeyPlatformAuthorizationCoordinator: ASAuthorizationController async bridge
│   └── Account/
│       ├── AccountViewModel.swift              # AccountPasskeyEnrollment: passkey add state
│       └── AccountView.swift                   # AccountPasskeyEnrollment: passkey add action / notice
├── Feedman.entitlements                        # AssociatedDomainsConfiguration: webcredentials domain
└── Info.plist                                  # 既存 URL scheme は維持、必要なら config key 追加

FeedmanTests/
├── PasskeyRepositoryTests.swift                # PasskeyRepository request/response tests / RegressionCoverage
├── PasskeyPlatformAuthorizationCoordinatorTests.swift
│                                               # PasskeyPlatformAuthorizationCoordinator parsing/mock boundary tests / RegressionCoverage
├── LoginViewModelTests.swift                   # LoginPasskeyFlow regression / RegressionCoverage
├── AccountViewModelTests.swift                 # AccountPasskeyEnrollment regression / RegressionCoverage
├── AccountViewTests.swift                      # 既存削除導線 preservation / RegressionCoverage
└── AppEnvironmentSessionRestoreTests.swift     # AuthStateIntegration / UserResponse username fallback / RegressionCoverage

Feedman.xcodeproj/
└── project.pbxproj                             # AssociatedDomainsConfiguration と新規 Swift files を target 登録
```

### Modified Files

- `Feedman/Core/APIModels.swift` — `PasskeyRegistrationBeginRequest`、distinct な `PasskeyRegistrationBeginResponse` / `PasskeyRegistrationFinishResponse(userID)` / `PasskeyAuthenticationBeginResponse` / `PasskeyAddRegistrationBeginResponse`、`PasskeyAuthenticationFinishResponse`、完全な WebAuthn JSON `PasskeyCredentialEnvelope`、`UserResponse.username?` を追加する。
- `Feedman/Core/PasskeyRepository.swift` — 新規。unauthenticated registration/authentication endpoint と Bearer 付き add endpoint を `APIClient` へ委譲する。
- `Feedman/Features/Login/PasskeyPlatformAuthorizationCoordinator.swift` — 新規。Apple platform passkey request/response、presentation anchor、cancel propagation と server DTO の変換境界。
- `Feedman/Features/Login/LoginViewModel.swift` — Google flow を維持しつつ passkey login/signup state と `PasskeyAuthCodeHandoff` を追加する。
- `Feedman/Features/Login/LoginView.swift` — Google primary、passkey login secondary、signup form/sheet を追加する。
- `Feedman/Features/Account/AccountViewModel.swift` — passkey add state、success notice、failure mapping を追加する。
- `Feedman/Features/Account/AccountView.swift` — passkey add action を追加し、existing logout/delete account actions を維持する。
- `Feedman/Core/AppEnvironment.swift` — production wiring に `PasskeyRepository` dependency を追加する。
- `Feedman/Feedman.entitlements` — Associated Domains entitlement を追加する。
- `Feedman.xcodeproj/project.pbxproj` — new files、entitlements、`CODE_SIGN_ENTITLEMENTS`、必要な build setting を登録する。

## Requirements Traceability

| Requirement | Summary | Components | Interfaces | Flows |
|-------------|---------|------------|------------|-------|
| 1.1 | Login 3 導線 | LoginPasskeyUI | View state | Login presentation |
| 1.2 | Google flow 維持 | LoginPasskeyFlow | existing `startGoogleLogin` | Google login |
| 1.3 | Passkey 副導線 | LoginPasskeyUI | Button style | Login presentation |
| 1.4 | Signup 導線文言 | LoginPasskeyUI | Signup form state | Signup presentation |
| 1.5 | duplicate guard | LoginPasskeyFlow, AccountPasskeyEnrollment | State guard | All ceremonies |
| 1.6 | Dynamic Type / VoiceOver | LoginPasskeyUI | Accessibility labels | UI rendering |
| 2.1 | username only / no email | LoginPasskeyFlow, LoginPasskeyUI | Signup input | Registration begin |
| 2.2 | local username validation | LoginPasskeyFlow | Validation state | Signup submit |
| 2.3 | registration begin + PKCE | PasskeyRepository, LoginPasskeyFlow | `registrationBegin` | Registration begin |
| 2.4 | registration platform request | PasskeyPlatformAuthorizationCoordinator | `performRegistration` | Platform registration |
| 2.5 | registration finish | PasskeyRepository | `registrationFinish` | Registration finish |
| 2.6 | signup local credential-bound login handoff | PasskeyPlatformAuthorizationCoordinator, PasskeyAuthCodeHandoff, AuthStateIntegration | local `allowedCredentials` + `auth_code` | Registration to login |
| 2.7 | username error before platform credential | LoginPasskeyFlow, PasskeyRepository | Error mapping | Signup failure |
| 2.8 | registration cancel/failure/result unknown | LoginPasskeyFlow | Cancellation/result-unknown mapping | Signup failure |
| 3.1 | passkey PKCE | LoginPasskeyFlow | PKCE generator | Authentication begin |
| 3.2 | authentication begin | PasskeyRepository | `authenticationBegin` | Authentication begin |
| 3.3 | assertion request | PasskeyPlatformAuthorizationCoordinator | `performAssertion` | Platform assertion |
| 3.4 | authentication finish | PasskeyRepository | `authenticationFinish` | Authentication finish |
| 3.5 | auth_code exchange | PasskeyAuthCodeHandoff, AuthStateIntegration | `exchangeAuthCode` | Token handoff |
| 3.6 | authenticated shell | AuthStateIntegration | `completeLogin` | Route handoff |
| 3.7 | auth failure | LoginPasskeyFlow | Error mapping | Authentication failure |
| 4.1 | account add action | AccountPasskeyEnrollment | View state | Account sheet |
| 4.2 | add begin Bearer | PasskeyRepository | `registrationAddBegin` | Add begin |
| 4.3 | add platform request | PasskeyPlatformAuthorizationCoordinator | `performRegistration` | Add registration |
| 4.4 | add finish Bearer | PasskeyRepository | `registrationAddFinish` | Add finish |
| 4.5 | add success notice | AccountPasskeyEnrollment | Notice state | Add success |
| 4.6 | add failure/result unknown session preservation | AccountPasskeyEnrollment | Error mapping | Add failure |
| 4.7 | refresh retry delegation | PasskeyRepository | APIClient hook | Add endpoint 401 |
| 5.1 | entitlement exists | AssociatedDomainsConfiguration | `CODE_SIGN_ENTITLEMENTS` | Build config |
| 5.2 | webcredentials domain | AssociatedDomainsConfiguration | Entitlements array | Build config |
| 5.3 | AASA app id alignment | AssociatedDomainsConfiguration | Config note | App Store prep |
| 5.4 | unknown domain not invented | AssociatedDomainsConfiguration | PR confirmation | Build config |
| 5.5 | entitlement mismatch failure | PasskeyPlatformAuthorizationCoordinator | Error mapping | Platform failure |
| 6.1 | refresh token storage | AuthStateIntegration | TokenStore | Token exchange |
| 6.2 | access token handoff | AuthStateIntegration | AppEnvironment | Token exchange |
| 6.3 | timeline compatibility | RegressionCoverage | Existing repositories | Post-login smoke |
| 6.4 | feed list compatibility | RegressionCoverage | Existing repositories | Post-login smoke |
| 6.5 | article detail / external article compatibility | RegressionCoverage | Existing UI + `SFSafariViewController` route | Post-login smoke |
| 6.6 | username account display | PasskeyAPIModels, AccountPasskeyEnrollment | `UserResponse.username` | Account loading |
| 6.7 | Google regression | RegressionCoverage | Existing tests | Google login |
| 7.1 | delete action visible | AccountPasskeyEnrollment, RegressionCoverage | AccountView | Account sheet |
| 7.2 | delete not redesigned | RegressionCoverage | Existing state | Account deletion |
| 7.3 | delete success unchanged | RegressionCoverage | Existing AppEnvironment | Account deletion |
| 7.4 | delete failure unchanged | RegressionCoverage | Existing error state | Account deletion |
| 8.1 | stack constraints | All components | SwiftUI / async / await | Implementation |
| 8.2 | View isolation | PasskeyRepository, PasskeyPlatformAuthorizationCoordinator | Protocol boundaries | Implementation |
| 8.3 | secret hygiene | PasskeyRepository, PasskeyPlatformAuthorizationCoordinator | DTO redaction | All ceremonies |
| 8.4 | cancellation mapping | LoginPasskeyFlow, AccountPasskeyEnrollment | Error mapping | All ceremonies |
| 8.5 | mockable tests | PasskeyRepository, PasskeyPlatformAuthorizationCoordinator | Protocol mocks | XCTest |
| 8.6 | regression tests | RegressionCoverage | XCTest | Verification |
| 8.7 | canonical xcodebuild | RegressionCoverage | Verify block | Verification |
| 8.8 | docs scope | RegressionCoverage | Diff review | Implementation scope |
| 8.9 | no advertising interaction collection | RegressionCoverage, LoginPasskeyFlow | PR confirmation / tests | App Store review |

## Components and Interfaces

### Core Auth / API

#### PasskeyAPIModels

| Field | Detail |
|-------|--------|
| Intent | サーバ #216 の passkey API payload と platform credential envelope を Codable 型として表現する |
| Requirements | 2.3, 2.5, 2.6, 3.2, 3.4, 4.2, 4.4, 6.6, 8.3 |

**Responsibilities & Constraints**
- WebAuthn options は go-webauthn の top-level `publicKey` wrapper を decode し、registration / authentication の response 型を分ける。`options.publicKey` が無い JSON は decode error として扱い、coordinator に曖昧な型を渡さない。
- Registration begin / authentication begin / add begin は同じ JSON shape に見えても distinct DTO とし、creation options と request options を enum discriminator なしで混在させない。
- `credential` envelope は WebAuthn JSON 互換の base64url field を保持する。raw Data は repository に渡す直前の DTO 変換に閉じ、ログ出力しない。
- `PasskeyRegistrationFinishResponse` はサーバ確定契約どおり `userID` のみを表現する。登録直後 handoff に使う credential ID はこの response ではなく、platform registration credential envelope の top-level `rawId` / `id` から取得する。
- `UserResponse.username` は optional とし、サーバが未返却でも既存 account loading を壊さない。

**Dependencies**
- Inbound: PasskeyRepository — request/response body construction (Critical)
- Outbound: APIClient — Codable encode/decode (Critical)
- External: Feedman API #216 — endpoint contract (Critical)

**Contracts**: API [x] / State [x]

##### API Contract

| Method | Endpoint | Request | Response | Errors |
|--------|----------|---------|----------|--------|
| POST | `/api/passkey/registration/begin` | `{ username, code_challenge }` | `{ challenge_id, options: { publicKey } }` | 400, 409, 429, 500 |
| POST | `/api/passkey/registration/finish` | `{ challenge_id, credential }` | `{ user_id }` | 400, 429, 500 |
| POST | `/api/passkey/authentication/begin` | `{ code_challenge }` | `{ challenge_id, options: { publicKey } }` | 400, 429, 500 |
| POST | `/api/passkey/authentication/finish` | `{ challenge_id, credential }` | `{ auth_code }` | 400, 429, 500 |
| POST | `/api/passkey/registration/add/begin` | `{}` + Bearer | `{ challenge_id, options: { publicKey } }` | 401, 400, 500 |
| POST | `/api/passkey/registration/add/finish` | `{ challenge_id, credential }` + Bearer | 204 | 401, 400, 500 |

#### PasskeyRepository

| Field | Detail |
|-------|--------|
| Intent | Passkey endpoint 群を `APIClient` に委譲し、mock と real implementation を差し替える |
| Requirements | 2.3, 2.5, 2.6, 3.2, 3.4, 4.2, 4.4, 4.7, 8.2, 8.5 |

**Responsibilities & Constraints**
- Unauthenticated begin/finish は access token を付けない。
- Add begin/finish は current access token を受け取り、既存 APIClient refresh retry hook に委譲する。
- Error response は `FeedmanAPIError` を ViewModel が扱える domain error へ写像できる形で伝播する。

**Dependencies**
- Inbound: LoginPasskeyFlow, AccountPasskeyEnrollment — ceremony API calls (Critical)
- Outbound: APIClient — HTTP request, decoding, refresh retry (Critical)
- External: Feedman API #216 — passkey endpoint (Critical)

**Contracts**: Service [x] / API [x]

##### Service Interface

```swift
protocol PasskeyRepository {
    func beginRegistration(username: String, codeChallenge: String) async throws -> PasskeyRegistrationBeginResponse
    func finishRegistration(challengeID: String, credential: PasskeyCredentialEnvelope) async throws -> PasskeyRegistrationFinishResponse
    func beginAuthentication(codeChallenge: String) async throws -> PasskeyAuthenticationBeginResponse
    func finishAuthentication(challengeID: String, credential: PasskeyCredentialEnvelope) async throws -> PasskeyAuthenticationFinishResponse
    func beginAddingCredential(accessToken: String) async throws -> PasskeyAddRegistrationBeginResponse
    func finishAddingCredential(accessToken: String, challengeID: String, credential: PasskeyCredentialEnvelope) async throws
}
```

- Preconditions: username は LoginPasskeyFlow で空白 validation 済み。Bearer endpoint には non-empty access token を渡す。
- Postconditions: repository は token を保存しない。token storage は AuthRepository の責務。
- Invariants: endpoint path と JSON key は #216 contract に一致する。`authentication/begin` に `credential_id` などの未知 field を送らない。登録直後 continuation の credential 制限は repository request ではなく coordinator の platform assertion request に閉じる。

#### PasskeyAuthCodeHandoff

| Field | Detail |
|-------|--------|
| Intent | Passkey signup / login の結果を既存 `AuthRepository.exchangeAuthCode` と `AppEnvironment.completeLogin` へ安全に合流させる |
| Requirements | 2.6, 3.5, 3.6, 6.1, 6.2, 8.3, 8.5 |

**Responsibilities & Constraints**
- `registration/finish` の `{user_id}` は登録完了確認として扱い、token exchange には使わない。
- Platform registration credential envelope から作成直後 credential ID を保持し、同じ in-flight PKCE の `code_challenge` で通常の `authentication/begin` を呼ぶ。
- Authentication begin response から作る platform assertion request にだけ作成直後 credential ID を `allowedCredentials` として適用し、assertion finish の `auth_code` を既存 token exchange に渡す。
- 作成直後 credential ID を envelope から取得できない場合、または credential-bound assertion が空の discoverable request にしかならない場合は result-unknown / contract mismatch として authenticated transition しない。

**Dependencies**
- Inbound: LoginPasskeyFlow — registration / authentication success handoff (Critical)
- Outbound: PasskeyRepository, PasskeyPlatformAuthorizationCoordinator, AuthRepository, AppEnvironment (Critical)
- External: Feedman API #216 registration/authentication contract (Critical)

**Contracts**: Service [x] / State [x]

##### Service Interface

```swift
protocol PasskeyAuthCodeHandoff {
    func completeSignupHandoff(
        finishResponse: PasskeyRegistrationFinishResponse,
        createdCredentialID: String,
        codeVerifier: String,
        codeChallenge: String
    ) async throws -> TokenCredentials
    func completeAuthenticationHandoff(authCode: String, codeVerifier: String) async throws -> TokenCredentials
}
```

- Preconditions: `codeVerifier` / `codeChallenge` は同一 attempt の in-flight PKCE pair。
- Postconditions: 成功時のみ `TokenCredentials` を返し、呼び出し元が `completeLogin` へ渡す。
- Invariants: raw `auth_code` / `code_verifier` を log / persist しない。

### Platform Authentication

#### PasskeyPlatformAuthorizationCoordinator

| Field | Detail |
|-------|--------|
| Intent | Server WebAuthn options と AuthenticationServices platform passkey request/response を async 境界で接続する |
| Requirements | 2.4, 2.6, 2.8, 3.3, 3.7, 4.3, 4.6, 5.5, 8.1, 8.3, 8.4, 8.5 |

**Responsibilities & Constraints**
- `ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier:)` を使い、registration は challenge/name/userID、authentication は challenge から request を作る。
- `excludeCredentials` は server options から descriptor ID だけを base64url decode して保持し、AuthenticationServices が platform registration request で受け付ける OS では best-effort に反映する。iOS 16〜17.3 では client-side duplicate prevention を保証できず、サーバ #216 は同一ユーザーへの複数 credential を許容するため server-side duplicate rejection を fallback とみなさない。この degraded behavior では「同一端末に追加 credential が作られ得るが、iOS は raw credential を保存せず server を source of truth とする」と明示し、複数 credential 管理 UI は本 Issue のスコープ外に留める。
- Authentication request の `allowCredentials` は通常 login では empty を許容するが、signup handoff では platform registration credential envelope の top-level `rawId` / `id` から得た作成直後 credential ID を必ず制限として渡す。この制限は `ASAuthorizationPlatformPublicKeyCredentialAssertionRequest` にだけ適用し、サーバ `authentication/begin` request へは送らない。
- `ASAuthorizationControllerDelegate` と `ASAuthorizationControllerPresentationContextProviding` を coordinator 内の bridge object に閉じ、`ASAuthorizationController.presentationContextProvider` へ設定してから `performRequests()` する。Apple API は delegate / presentation context provider を weak に保持するため、coordinator は attempt 中に `ActiveAuthorizationAttempt` を強参照し、その中で `ASAuthorizationController`、delegate bridge、presentation context provider bridge をまとめて保持する。presentation anchor は active `UIWindow` / `ASPresentationAnchor` を返す provider closure で UI layer から注入し、anchor を取得できない場合は `performRequests()` を呼ばず `.presentationAnchorUnavailable` を throw して retryable platform failure として表示する。
- `PasskeyPlatformAuthorizationCoordinator` は UI presentation と `ASAuthorizationController` callback を扱うため `@MainActor` に隔離する。`ActiveAuthorizationAttempt` は delegate success / failure、または coordinator deinit のいずれかで exactly-once に continuation を resume してから nil にし、bridge/provider を解放して次 attempt へ参照を持ち越さない。
- Async bridge は `withTaskCancellationHandler` で `ASAuthorizationController.cancel()` を呼ぶ。Apple API は active request の cancel 結果を delegate error callback で通知するため、明示 cancel / Task cancellation 直後に `ActiveAuthorizationAttempt` を nil にしない。Callback まで attempt を保持するか、callback を待てない coordinator deinit では continuation を `.canceled` で exactly-once resume してから解放する。Delegate success が返った後でも、registration/add finish、authentication finish、token exchange の直前に caller 側 attempt ID と `Task.isCancelled` を再確認し、cancel 済みなら後続 server finish を送らない。
- User cancellation は domain error `.canceled`、entitlement/AASA mismatch や validation failure は `.failed` に分類する。
- Credential response は WebAuthn JSON compatible envelope に変換し、top-level `id` / `rawId` / `type` と `response.clientDataJSON` を registration / assertion とも必ず含める。raw bytes は log / persistent storage に渡さない。

**Dependencies**
- Inbound: LoginPasskeyFlow, AccountPasskeyEnrollment — platform ceremony start (Critical)
- Outbound: AuthenticationServices — platform UI and credential result (Critical)
- External: Associated Domains / AASA — RP verification (Critical)

**Contracts**: Service [x]

##### Service Interface

```swift
@MainActor
protocol PasskeyPlatformAuthorizationCoordinating {
    func performRegistration(options: PasskeyPublicKeyCredentialCreationOptions) async throws -> PasskeyCredentialEnvelope
    func performAssertion(options: PasskeyPublicKeyCredentialRequestOptions, allowedCredentialID: String?) async throws -> PasskeyCredentialEnvelope
    func cancelActiveAuthorization()
}
```

- Preconditions: options の `challenge`、registration `user.id`、credential descriptor ID は base64url decode 可能。`rp.id` / `rpId` は decode せず relying party domain string として `ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier:)` に渡す。presentation anchor provider が non-nil anchor を返す。
- Postconditions: 成功時は server finish request に送れる credential envelope を返す。
- Invariants: Coordinator は API request を送らず、token / username / email を保存しない。Active attempt 以外では `ASAuthorizationController`、delegate bridge、presentation provider bridge への強参照を保持しない。

### Login Feature

#### LoginPasskeyFlow

| Field | Detail |
|-------|--------|
| Intent | 未認証 login screen の Google / passkey login / passkey signup state machine を管理する |
| Requirements | 1.2, 1.5, 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 2.8, 3.1, 3.2, 3.5, 3.6, 3.7, 8.4, 8.5, 8.9 |

**Responsibilities & Constraints**
- 既存 `startGoogleLogin()` の behavior を維持する。
- `startPasskeyLogin()` は PKCE → authentication begin → platform assertion → authentication finish → `AuthRepository.exchangeAuthCode` → `onAuthenticated` の順に実行する。
- `startPasskeyRegistration(username:)` は username validation → PKCE → registration begin → platform registration → registration finish `{user_id}` → authentication begin `{code_challenge}` → 作成直後 credential ID で制限した platform assertion → authentication finish `{auth_code}` → token exchange の順に実行する。`authentication/begin` へ `credential_id` を送らず、作成直後 credential ID が platform registration envelope から取得できない場合は authenticated transition せず result-unknown error とする。
- In-flight 状態を 1 つに集約し、Google / passkey の同時実行を防ぐ。
- View / sheet dismissal などで in-flight `Task` が cancel された場合は coordinator の active authorization を cancel し、platform callback 後の race に備えて registration finish、authentication finish、token exchange の直前に attempt ID と cancellation を確認する。`registration/finish` の dispatch 前に cancel を検知した場合は `.canceled` state を表示し、`idle` へ黙って戻さない。`registration/finish` dispatch 後に cancel / timeout / decode failure で完了状態を観測できない場合は、サーバ側で登録済みになり得るため `.resultUnknown` 相当の failed state として扱い、未ログイン状態を維持しつつ「再試行またはパスキーログインで照合できる」文言を出す。
- `AuthRepository.exchangeAuthCode` の呼び出し開始後は、refresh token 保存と `AppEnvironment.completeLogin` の分離を避けるため token exchange → `completeLogin` を non-cancelable auth critical section として扱う。View dismissal / sheet dismissal 由来の cancellation は token exchange dispatch 前までしか login attempt を止めず、dispatch 後に token exchange が成功した場合は必ず `completeLogin` まで進めて authenticated route へ遷移する。Token exchange が error を返した場合だけ既存 login failure と同じ `.failed` にし、保存済み token と未認証 route が分離しないよう既存 `AuthRepository` の保存完了後成功戻り値を `completeLogin` と同じ attempt-local critical section 内で処理する。
- Passkey login option 自体は app interaction を広告目的で収集しない。実装 PR では passkey flow に analytics / ad SDK event を追加しないことを diff review と tests で確認する。

**Dependencies**
- Inbound: LoginPasskeyUI — user actions (Critical)
- Outbound: PasskeyRepository, PasskeyPlatformAuthorizationCoordinator, AuthRepository, PKCELoginChallengeGenerating (Critical)
- External: Feedman API #216, AuthenticationServices (Critical)

**Contracts**: Service [x] / State [x]

##### State Contract

```swift
enum LoginViewState {
    case idle
    case loading(LoginAttemptKind)
    case authenticated
    case canceled(LoginAttemptKind)
    case failed(LoginAttemptKind, String)
    case resultUnknown(LoginAttemptKind, String)
}
```

- Preconditions: `state.isLoading == false` のときのみ新しい attempt を開始する。
- Postconditions: 成功時だけ `onAuthenticated(credentials)` を呼ぶ。
- Invariants: 失敗・キャンセル・result-unknown 時は in-flight PKCE verifier と challenge_id を破棄する。`registrationFinishDispatched`、`authenticationFinishDispatched`、`tokenExchangeDispatched` など送信済み marker は attempt-local に保持し、finish dispatch 前 cancellation は `.canceled`、finish dispatch 後 cancellation / transport timeout / decode failure は `.resultUnknown` へ map する。`tokenExchangeDispatched` 後は cancellation を result-unknown にせず、exchange success なら `completeLogin` まで不可分に進める。iOS が作成済み platform credential を削除できる前提には置かず、server を source of truth として次の retry / login で照合する。

#### LoginPasskeyUI

| Field | Detail |
|-------|--------|
| Intent | Login screen に Google primary、passkey secondary、signup form を表示する |
| Requirements | 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2 |

**Responsibilities & Constraints**
- 既存 Feedman branding と 8px radius / FeedmanTheme を維持する。
- Google button を主ボタン、passkey login を secondary outline、signup を text/secondary action とする。
- Signup は sheet または inline compact form。username 以外の個人情報 input は置かない。
- `LoginViewState.resultUnknown` は `.failed` と別表示にし、「アカウント作成結果を確認できませんでした。再試行またはパスキーでログインして照合してください」のようにサーバ照合を促す日本語文言を出す。Dynamic Type / VoiceOver でも loading / canceled / failed と同じ状態表示領域で重ならないことを確認する。
- Long username error / Dynamic Type / VoiceOver label が重ならない layout にする。

**Dependencies**
- Inbound: RootView unauthenticated route (Important)
- Outbound: LoginPasskeyFlow — actions and state (Critical)
- External: SwiftUI (Critical)

**Contracts**: State [x]

### Account Feature

#### AccountPasskeyEnrollment

| Field | Detail |
|-------|--------|
| Intent | 認証済み Account sheet から passkey 追加登録を実行し、既存 logout/delete actions を維持する |
| Requirements | 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 6.6, 7.1, 7.2, 7.3, 7.4, 8.4 |

**Responsibilities & Constraints**
- `AccountViewModel` に `PasskeyEnrollmentState`（idle / adding / canceled / failed / resultUnknown / succeeded）を追加する。
- Add begin/finish は access token 必須。missing token は認証切れ error として表示する。
- Success は `actionNotice` または既存 notice pattern で表示し、authenticated session は維持する。
- `PasskeyEnrollmentState.resultUnknown` は canceled / failed / succeeded と別表示にし、「追加済みか確認できません。現在のセッションは維持されています。再試行または次回パスキーログインで照合してください」のようにサーバ照合を促す notice / error を表示する。
- Existing logout / delete account state と混同せず、delete action を削除しない。
- Passkey add / logout / account deletion は共同 guard を持つ。add が `.adding` の間は logout と delete action を disabled にし、logout または delete confirmation が進行中なら add を開始しない。ユーザーが sheet dismissal などで add ceremony を離脱した場合は `Task.cancel()` と `PasskeyPlatformAuthorizationCoordinating.cancelActiveAuthorization()` を呼ぶ。Add finish dispatch 前に cancellation check が検知した場合は finish request を送らず `.canceled` にするが、add finish dispatch 後に cancellation / timeout / decode failure で完了状態を観測できない場合は server 側で追加済みになり得るため `.resultUnknown` にする。

**Dependencies**
- Inbound: AccountView — add action (Critical)
- Outbound: PasskeyRepository, PasskeyPlatformAuthorizationCoordinator, APIClient refresh retry (Critical)
- External: AuthenticationServices (Critical)

**Contracts**: Service [x] / State [x]

##### State Contract

```swift
enum PasskeyEnrollmentState {
    case idle
    case adding
    case canceled(AccountErrorViewState)
    case failed(AccountErrorViewState)
    case resultUnknown(AccountErrorViewState)
    case succeeded
}
```

- Preconditions: current user loaded かつ non-empty access token。logoutState / deletionState が in-flight でない。
- Postconditions: 成功・失敗・キャンセル・result-unknown のいずれでも current auth session を維持する。キャンセルは `.canceled` として server / validation failure とは別表示にし、retry 可能な文言を出す。add finish dispatch 後の cancellation / transport timeout / decode failure は `.resultUnknown` として扱い、server を source of truth として再試行または次回パスキーログインで照合する文言を出す。ただし user が明示的に logout / delete を開始した後は新しい add ceremony を開始しない。
- Invariants: deletionState / logoutState の挙動を変更しない。

### Configuration / Integration

#### AssociatedDomainsConfiguration

| Field | Detail |
|-------|--------|
| Intent | App target に Associated Domains entitlement を追加し、server AASA と RP ID を整合させる |
| Requirements | 5.1, 5.2, 5.3, 5.4, 5.5 |

**Responsibilities & Constraints**
- `Feedman/Feedman.entitlements` を追加し、`com.apple.developer.associated-domains` に `webcredentials:$(FEEDMAN_WEBCREDENTIALS_DOMAIN)` を設定する。
- `FEEDMAN_WEBCREDENTIALS_DOMAIN` は server #216 の `WEBAUTHN_RP_ID` と同じ fully qualified domain とする。repo 内に正本が無いため Developer は値を発明しない。
- `CODE_SIGN_ENTITLEMENTS = Feedman/Feedman.entitlements` を app target Debug/Release に設定する。
- `TEAM_ID.com.hitoshiichikawa.feedman` が AASA の `webcredentials.apps` に含まれることを App Store build 準備時に確認する。

**Dependencies**
- Inbound: Xcode build/signing (Critical)
- Outbound: Server AASA (Critical)
- External: Apple Associated Domains entitlement (Critical)

**Contracts**: Infrastructure [x]

#### AuthStateIntegration

| Field | Detail |
|-------|--------|
| Intent | Passkey 由来 `auth_code` を既存 token exchange と route handoff に接続する |
| Requirements | 3.5, 3.6, 6.1, 6.2, 6.3, 6.4, 6.5, 6.7 |

**Responsibilities & Constraints**
- Passkey 独自 token endpoint を作らない。
- `AuthRepository.exchangeAuthCode` が refresh token 保存を担う。
- `AppEnvironment.completeLogin` が in-memory access token と route transition を担う。
- Token exchange dispatch 後は `AuthRepository.exchangeAuthCode` success と `AppEnvironment.completeLogin` を同一 auth critical section として扱い、UI dismissal cancellation で中断しない。これにより refresh token 保存済み・未認証 route の分離を防ぐ。
- Timeline / Feed / ArticleDetail / `SFSafariViewController` の外部記事表示は login method を知らないまま既存 Bearer token と既存 article open flow を使う。

**Dependencies**
- Inbound: LoginPasskeyFlow — auth_code handoff (Critical)
- Outbound: AuthRepository, AppEnvironment, existing feature repositories (Critical)
- External: `/api/auth/token` existing contract (Critical)

**Contracts**: Service [x] / State [x]

#### RegressionCoverage

| Field | Detail |
|-------|--------|
| Intent | 認証方式追加による Google login、account deletion、主要 feature regression を XCTest と verify で固定する |
| Requirements | 5.2, 5.3, 6.3, 6.4, 6.5, 6.7, 7.1, 7.2, 7.3, 7.4, 8.5, 8.6, 8.7, 8.8, 8.9 |

**Responsibilities & Constraints**
- Mock repository / mock coordinator を使い real network / Keychain / Face ID に依存しない。
- Existing LoginViewModelTests / AccountViewModelTests を拡張し、既存 behavior の不変性を明示する。
- Project file と entitlements は `plutil` で構文確認する。
- `AppEnvironment.production` から `LoginRouteView` / `AccountRouteView` / `completeLogin` までの dependency wiring を integration test または compile-time injection test で確認する。
- Authenticated shell regression は Timeline / Feed / ArticleDetail sheet に加え、ArticleDetail から `SFSafariViewController` で元記事を開く既存 route を対象に含める。
- Passkey flow に analytics / ad SDK event を追加していないことを差分レビューで確認し、既存 analytics hook がある場合は passkey event が広告目的収集に使われないことを PR 確認事項に残す。
- AASA / Associated Domains は plist 構文だけでは検出できないため、production/staging RP domain と署名済み実機 build で manual smoke を行う。実行できない場合は `WEBAUTHN_RP_ID`、Team ID、AASA `webcredentials.apps` の未確認事項を PR に残す。

**Dependencies**
- Inbound: Developer verification (Critical)
- Outbound: XCTest, xcodebuild, plutil, git diff check (Critical)
- External: Xcode simulator availability (Important)

**Contracts**: Batch [x]

## Data Models

### Domain Model

- `PasskeyRegistrationBeginResponse`: `challengeID` と `options.publicKey` の creation options を保持する。
- `PasskeyAuthenticationBeginResponse`: `challengeID` と `options.publicKey` の request options を保持する。
- `PasskeyAddRegistrationBeginResponse`: `challengeID` と `options.publicKey` の creation options を保持する。registration と同じ shape でも add flow 用に distinct type とする。
- `PasskeyPublicKeyCredentialCreationOptions`: `rp.id`、`user.name`、`user.id`、`challenge`、`excludeCredentials` を保持する。`challenge` と `user.id` と `excludeCredentials[].id` は base64url → `Data` へ変換して platform registration request / descriptor に渡す。`rp.id` は relying party domain string であり base64url decode しない。`excludeCredentials` を platform request に適用できない OS では duplicate prevention は保証されない degraded behavior とし、server-side duplicate rejection を前提にしない。
- `PasskeyPublicKeyCredentialRequestOptions`: `rpId`、`challenge`、server options の `allowCredentials` を保持する。通常の passkey login は discoverable login として `allowCredentials` 空を許容するが、signup handoff は coordinator 呼び出し時に作成直後 credential ID をローカル override として渡し、空の `allowCredentials` に fallback しない。
- `PasskeyCredentialEnvelope`: finish endpoint へ送る WebAuthn compatible credential JSON。top-level は `id`、`rawId`、`type: "public-key"`、`response`、任意の `clientExtensionResults` / `authenticatorAttachment` を持つ。registration response は `clientDataJSON` と `attestationObject` を必須とし、go-webauthn が受理する場合に限り `transports`、`authenticatorData`、`publicKey`、`publicKeyAlgorithm` も保持する。assertion response は `clientDataJSON`、`authenticatorData`、`signature`、任意の `userHandle` を持つ。全 binary field は base64url 文字列として encode/decode し、unit test で padding 有無と missing required field を検証する。
- `PasskeyRegistrationFinishResponse`: `userID` を持つ。登録完了確認専用であり、`authCode` や server-returned `credentialID` を表現しない。
- `PasskeyAuthenticationFinishResponse`: `authCode` を保持し、既存 `AuthRepository.exchangeAuthCode` に渡す。
- `UserResponse.username`: optional。Account display は `name` → `username` → `email` → fallback の順に displayName を決める。

### Logical / Physical Data Model

ローカル永続データは追加しない。Platform passkey credential は iOS / iCloud Keychain 側が管理し、Feedman iOS は raw credential を永続化しない。Platform registration 成功後は iOS 側で credential が作成済みになり得るため、`registration/finish` / add finish の失敗時に「credential を削除する」設計にはしない。Server side credential / challenge / AASA は #216 の責務であり、server を source of truth として次の retry / login で照合する。

## Error Handling

### Error Strategy

- Platform cancellation: platform authorization 中または finish dispatch 前の cancellation は `.canceled` として扱い、未ログイン flow では login screen、Account add では account sheet に専用 canceled state / notice を表示する。`ASAuthorizationController.cancel()` と finish 前 cancellation check で後続 server finish / token exchange を止め、token exchange や local credential clear は実行しない。finish dispatch 後は cancellation だけでは server side mutation の有無を断定できないため result-unknown に分類する。Token exchange dispatch 後だけは例外として、既存 `AuthRepository.exchangeAuthCode` が refresh token 保存を担うため cancellation を無視して `completeLogin` まで進め、保存済み token と未認証 route を分離させない。
- Input validation: empty または whitespace-only username は trim 後 client side で止める。server の `INVALID_USERNAME` / `USERNAME_TAKEN` は signup form に修正可能 error として表示する。
- Ceremony failure: `REGISTRATION_FAILED` / `AUTHENTICATION_FAILED`、AASA mismatch、expired challenge、unknown credential は server を source of truth とする retry 可能 error にする。Platform credential が既に作成済みの可能性を UI 文言で否定しない。
- Result-unknown finish: platform registration 成功後に `registration/finish` / add finish が dispatch 済みで、Task cancellation、timeout、network lost、decode failure により結果不明になった場合、iOS は raw credential を保存せず、signup では未ログイン状態、add では current session 維持に留める。次の retry または passkey login で server state を照合する。
- Token exchange failure: passkey finish が成功しても token exchange に失敗した場合は既存 login failure と同様に authenticated transition しない。Token exchange dispatch 後に exchange が成功した場合は dismissal cancellation があっても `completeLogin` を実行する。
- Account add failure: current session と refresh token を保持する。Add flow 失敗を logout / account deletion と混同せず、add / logout / delete の共同 guard で finish と失効 token / 退会を競合させない。

### Error Categories and Responses

- **User Errors (4xx)**: empty / whitespace-only username、invalid username、username taken、canceled passkey ceremony。入力修正または再試行を案内する。
- **System Errors (5xx)**: passkey endpoint 500、network failure、decode failure、finish result-unknown。既存文言に合わせ「時間をおいて再試行」を表示し、必要なら「パスキーでログインを試す」導線へ戻す。
- **Business Logic Errors (422 相当)**: server contract は 400 `REGISTRATION_FAILED` / `AUTHENTICATION_FAILED` を返す想定。詳細を出さず、credential 未登録・期限切れ・認証失敗を uniform に扱う。

## Testing Strategy

- **Unit Tests**:
  - `PasskeyRepositoryTests`: 6 endpoint の method/path/body/Bearer header、401 refresh retry 委譲、distinct begin DTO、`options.publicKey` decode、204 no-content、error propagation。
  - `PasskeyPlatformAuthorizationCoordinatorTests`: base64url decode 対象が `challenge` / `user.id` / credential descriptor ID に限定され `rp.id` を decode しないこと、registration/assertion credential envelope conversion（`id` / `rawId` / `type` / `clientDataJSON` 必須）、presentation anchor unavailable error、attempt 中の controller / delegate bridge / presentation provider bridge lifetime、cancel callback までの attempt retention、continuation exactly-once resume、completion / cancel 後の release、`ASAuthorizationController.cancel()` propagation、cancellation mapping、`excludeCredentials` 反映可能 OS の best-effort 適用、iOS 16〜17.3 degraded behavior。
  - `LoginViewModelTests`: passkey login success/failure/cancel、signup validation、empty username と whitespace-only username が server request を送らないこと、`INVALID_USERNAME` と `USERNAME_TAKEN` 分岐、signup local credential-bound continuation、registration envelope missing credential ID result-unknown、registration finish dispatch 前 cancellation は canceled、dispatch 後 cancellation / timeout / decode failure は result-unknown、View / signup sheet dismissal cancel 後に未送信の registration/authentication finish と token exchange を呼ばない race guard、token exchange dispatch 後の cancellation では exchange success から `completeLogin` まで進む critical section、duplicate guard、Google regression。
  - `AccountViewModelTests`: add begin/finish success、success notice、dedicated canceled state、dedicated resultUnknown state、add finish dispatch 前 cancellation は canceled、dispatch 後 cancellation / timeout / decode failure は result-unknown、cancel/failure/result-unknown session preservation、missing token、auth-required after refresh retry failure、rate-limit、server failure の各表示、duplicate guard、logout/delete 共同 guard、401 refresh retry delegation、delete state 不変。
  - `AccountDisplayUser` tests: `name` → `username` → `email` → fallback precedence。
- **Integration Tests**:
  - `AppEnvironment` production wiring が `PasskeyRepository` を注入し、passkey login success で existing `completeLogin` に到達する。
  - `APIClient` refresh retry hook が add endpoint 401 で既存 hook に委譲される。
  - Project file / entitlements が `plutil` で valid。
  - Passkey flow が raw credential / token / verifier を logs、fixtures、analytics / ad SDK events に出さないことを mock logger / diff review で確認する。
- **E2E/UI Tests**:
  - Real Face ID / Touch ID を使う UI test は標準 XCTest では安定しないため追加しない。ViewModel と coordinator mock で critical path を検証する。
  - Manual smoke: production/staging backend と AASA が有効な署名済み実機 build で signup、login、add passkey、timeline/feed/article detail、`SFSafariViewController` の元記事表示、account deletion route を確認する。AASA / Team ID / RP domain 未確定なら PR 確認事項に残す。
- **Performance/Load**:
  - iOS 側は heavy local processing を持たない。Large credential JSON decode が UI thread を長時間 block しないことを ViewModel の async boundary で担保する。
  - Duplicate in-flight guard により同一ユーザー操作から begin/finish request を多重発行しない。

## Security Considerations

- Raw `auth_code`、`code_verifier`、access token、refresh token、attestation/assertion raw bytes、recovery email をログ、test fixture、error message に含めない。
- `code_verifier` と `challenge_id` は in-flight state のみで保持し、成功・失敗・キャンセルで破棄する。
- `PasskeyCredentialEnvelope` は server finish へ送る一時 DTO とし、ローカル永続化しない。
- Account add は current authenticated user の Bearer token でのみ実行し、missing token は repository 呼び出し前に拒否する。

## Supporting References

- App Store Review Guideline 4.8 / 5.1.1(v): <https://developer.apple.com/app-store/review/guidelines/#login-services>
- Apple passkey guide: <https://developer.apple.com/documentation/authenticationservices/connecting-to-a-service-with-passkeys>
- Apple fast account creation with passkeys: <https://developer.apple.com/documentation/authenticationservices/performing-fast-account-creation-with-passkeys>
- Associated Domains entitlement: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains>
- Apple platform passkey registration request: <https://developer.apple.com/documentation/authenticationservices/asauthorizationplatformpublickeycredentialregistrationrequest>
- ASAuthorizationController delegate: <https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller/delegate>
- ASAuthorizationController presentation context / cancel: <https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller>
- ASAuthorizationController weak presentation context provider: <https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller/presentationcontextprovider>
- ASAuthorizationControllerPresentationContextProviding: <https://developer.apple.com/documentation/authenticationservices/asauthorizationcontrollerpresentationcontextproviding>
- go-webauthn protocol `CredentialCreationResponse` / `CredentialAssertionResponse`: <https://pkg.go.dev/github.com/go-webauthn/webauthn/protocol>
- Server passkey design PR: <https://github.com/hitoshiichikawa/feedman/pull/217>
