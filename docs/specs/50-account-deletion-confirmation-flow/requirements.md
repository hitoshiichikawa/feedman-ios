# Issue #50 Account deletion confirmation flow 要件定義

## 背景

Issue #50 は Parent: #11 の子 Issue として、アカウントシートから退会を要求したユーザーに破壊的操作であることを確認し、確認後に `DELETE /api/users/me` を呼び、成功後に端末内の認証状態を消去してログイン画面へ戻す。

Issue 本文の期待する挙動は "Account deletion requires confirmation, calls delete endpoint, and clears local auth state." である。受入候補は、退会要求時に destructive confirmation を表示すること、確認時に `DELETE /api/users/me` を呼ぶこと、削除成功時に credentials を消去して login を表示することを示している。

`design/SPEC-iOS.md` では v1 スコープに「アカウント、ログアウト、退会」が含まれ、認証/ユーザー endpoint として `DELETE /api/users/me` が定義されている。また、アカウント画面の退会は `DELETE /api/users/me` と二段確認で実装する方針である。`design/SERVER.md` では、退会時にサーバー側の `refresh_tokens` / `auth_codes` が削除されることが受け入れ基準に含まれる。したがって iOS 側は退会 API 成功後に追加の revoke 成功を待たず、ローカル credential と authenticated session state を消去することを主要責務とする。

既存 Issue #48 はアカウントシートで current user を読み込み、ログアウト action と退会 action を表示するところまでを責務とし、退会の実挙動、`DELETE /api/users/me`、credential clear、login transition を明示的にスコープ外としていた。本 Issue はその後続として、既存の Account feature 境界に退会の実行 flow を接続する。

依存関係について、Issue #50 のコメントでは `idd-codex:dependency-auto-unblock:#50` により依存 Issue がすべて解消済みと記録されている。具体的には #48 の状態が `staged-for-release`、#49 の状態が `staged-for-release` であり、`codex-blocked` が自動解除されている。本 Issue の実装要件はこの依存解除済み状態を前提とする。

Path Overlap Checker の edit path は `Feedman/Features/Account/`、`Feedman/Core/`、`FeedmanTests/` である。

## スコープ

- Account sheet の退会 action から destructive confirmation を表示する。
- 退会実行前に、ユーザーが取り消し可能な確認段階を設ける。
- 確認後に認証付き APIClient / repository 境界を通じて `DELETE /api/users/me` を呼ぶ。
- 退会 API 実行中、成功、失敗の UI 状態を扱う。
- 退会成功時に local credentials を消去し、authenticated session state を未認証へ遷移させ、login 画面を表示する。
- 退会失敗時に local credentials と authenticated session state を保持し、ユーザーが再試行またはキャンセルできるようにする。
- ViewModel / repository protocol / mock を通じ、UI と API / Keychain 直接操作を分離する。
- XCTest で ViewModel と repository 境界の主要分岐を検証できる要件を定義する。

## スコープ外

- Profile editing。
- Account recovery。
- ユーザー情報の編集、avatar upload、メール変更。
- `GET /auth/me` の current user loading の新規実装または response shape 変更。
- ログアウト flow 全体の再設計。
- `POST /api/auth/revoke` のログアウト要件変更。
- `POST /auth/logout` の Cookie session logout 要件変更。
- サーバー側 `DELETE /api/users/me` の実装、DB cleanup、refresh token cascade の変更。
- account deletion 後の account recovery UI。
- multi-account switching。
- WebView Cookie login fallback。
- キーワード通知、OPML、フィード URL 変更 UI など v1 スコープ外機能。

## 要件

### Requirement 1: Destructive confirmation presentation

**Objective:** As a ログイン済みユーザー, I want 退会操作の前に破壊的操作であることを確認される, so that 誤操作でアカウントを削除しない

#### Acceptance Criteria

1. When the delete account action is tapped from the account sheet, the app shall destructive confirmation を表示する。
2. When the confirmation is shown, the confirmation shall アカウント削除が取り消せない操作であることを日本語で明示する。
3. When the confirmation is shown, the confirmation shall destructive confirm action と cancel action を提供する。
4. When the user cancels the confirmation, the app shall `DELETE /api/users/me` を呼ばず、local credentials と authenticated session state を変更しない。
5. When the confirmation is shown, the destructive confirm action shall iOS 標準または既存 DesignSystem の destructive 表現に沿う。
6. When Dynamic Type or VoiceOver is enabled, the confirmation shall 退会の結果、confirm、cancel を理解できる日本語表示または accessibility label を提供する。
7. When account sheet current user loading has failed or no authenticated session exists, the app shall delete account action を実行可能にしない、または実行前に認証切れとして扱う。

### Requirement 2: Account deletion API call

**Objective:** As a ログイン済みユーザー, I want 確認後にサーバー上の自分のアカウントが削除される, so that Feedman の退会処理が完了する

#### Acceptance Criteria

1. When the user confirms account deletion, the app shall `DELETE /api/users/me` を呼ぶ。
2. When `DELETE /api/users/me` is requested, the app shall Bearer token 認証付きの既存 APIClient / repository 境界を使う。
3. When account deletion is requested, the app shall View から `URLSession`、Keychain、raw token store を直接触らない。
4. When account deletion is in progress, the app shall duplicate confirm taps による重複 request を防ぐ。
5. When account deletion is in progress, the app shall progress state を表示し、退会実行中であることをユーザーに示す。
6. When the server returns any successful 2xx no-content or JSON response that APIClient treats as success, the app shall account deletion succeeded と扱う。
7. If the access token is expired, the request shall 既存 APIClient の 401 refresh retry hook に委ね、Account feature 内で独自 refresh を実装しない。
8. If the server returns a typed Feedman error response, the app shall 既存 error decoding / domain error mapping に沿ってユーザーに表示可能な日本語文言へ変換する。

### Requirement 3: Successful deletion clears local auth state

**Objective:** As a 退会済みユーザー, I want 端末に認証情報が残らずログイン画面へ戻る, so that 削除済みアカウントとしてアプリを使い続けない

#### Acceptance Criteria

1. When `DELETE /api/users/me` succeeds, the app shall local credentials を消去する。
2. When local credentials are cleared after account deletion, the app shall `TokenStore.clearCredentials()` 相当の既存 repository / environment 境界を使う。
3. When account deletion succeeds, the app shall in-memory access token を含む authenticated session state を未認証へ遷移させる。
4. When account deletion succeeds, login shall be shown。
5. When account deletion succeeds, the app shall account sheet と authenticated shell を閉じ、削除済み account data を表示し続けない。
6. When account deletion succeeds, the app shall `POST /api/auth/revoke` の成功を追加条件にしない。
7. When account deletion succeeds, the app shall `POST /auth/logout` の成功を追加条件にしない。
8. When account deletion succeeds, the app shall server-side deletion cleanup の成否を iOS から追加 API で検証しない。

### Requirement 4: Failure handling preserves session

**Objective:** As a ログイン済みユーザー, I want 退会に失敗した場合はログイン状態が保持される, so that 一時的な通信失敗で勝手にサインアウトされない

#### Acceptance Criteria

1. When `DELETE /api/users/me` fails before a success response is received, the app shall local credentials を消去しない。
2. When account deletion fails, the app shall authenticated session state を未認証へ遷移させない。
3. When account deletion fails, the app shall account sheet または account flow 上で error state を表示する。
4. When account deletion fails, the app shall retry 可能な導線、または confirmation へ戻れる導線を提供する。
5. When account deletion fails, the app shall duplicate in-flight request state を解除し、ユーザーが次の操作を選べるようにする。
6. If the failure indicates authentication loss after refresh retry, the app shall delete succeeded と扱わず、既存 session loss 方針に沿って credential clear / login transition を行うかを実装側で明示する。
7. If the network request is cancelled by dismissal or task cancellation before completion, the app shall delete succeeded と扱わず、local credentials を消去しない。

### Requirement 5: Account ViewModel and repository boundary

**Objective:** As a Developer, I want 退会 flow が Account feature の ViewModel と repository protocol で表現される, so that mock と real API を差し替えて検証できる

#### Acceptance Criteria

1. When account deletion behavior is introduced, the app shall Account repository protocol に delete current user 相当の境界を定義する。
2. When the real repository deletes the account, the repository shall API 契約 `DELETE /api/users/me` を使う。
3. When the mock repository is used, the app shall success / failure / delay を制御できるようにする。
4. When Account ViewModel owns deletion UI state, the ViewModel shall idle / confirming / deleting / failed / succeeded 相当の状態を明示的に表現する。
5. When Account ViewModel updates UI state from async work, the ViewModel shall `@MainActor` または同等の main actor 境界を明示する。
6. When account deletion succeeds, the ViewModel shall local credential clear と app session transition を既存 AppEnvironment / AuthRepository 境界へ依頼し、View が Keychain を直接触らない。
7. When existing #48 account sheet actions are connected, the implementation shall current user loading の責務を不必要に変更しない。
8. When existing #49 logout behavior exists, the implementation shall logout flow と account deletion flow の destructive action / loading state / session clear 境界を混同しない。

### Requirement 6: Tests and verification expectation

**Objective:** As a QA/Developer, I want 退会 flow の主要分岐が単体テストで固定される, so that 破壊的操作の回帰を検出できる

#### Acceptance Criteria

1. When account deletion ViewModel tests are added, the test suite shall mock repository と mock session environment を使い、実ネットワーク・実 Keychain に依存しない。
2. When delete account action is tapped, the test suite shall confirmation state に入ることを検証する。
3. When confirmation is cancelled, the test suite shall delete request、credential clear、login transition が発生しないことを検証する。
4. When confirmation is accepted and repository succeeds, the test suite shall delete request、credential clear、unauthenticated transition が発生することを検証する。
5. When repository fails, the test suite shall credential clear と unauthenticated transition が発生せず error state が残ることを検証する。
6. When duplicate confirm is attempted during deletion, the test suite shall delete request が多重発行されないことを検証する。
7. When repository tests are added, the test suite shall `DELETE /api/users/me` の method / path / Bearer 認証境界を検証する。
8. When Xcode test is available, the implementation shall `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` で検証する。
9. While Linux 環境または Xcode 未選択環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall iOS 16+ SwiftUI で動作する。
2. The implementation shall Swift Concurrency (`async` / `await`) を使う。
3. Swift の型名、識別子、ファイル名は English にする。
4. The implementation shall MVVM + Repository 方針に従う。
5. The implementation shall 既存 Bearer token 認証、401 refresh retry、TokenStore の契約を破壊しない。

### NFR 2: Scope control

1. The implementation shall Issue #50 の account deletion confirmation flow に閉じる。
2. The implementation shall Profile editing and account recovery を含めない。
3. The implementation shall `design/SPEC-iOS.md` と `design/SERVER.md` の API 契約を優先する。
4. The implementation shall `docs/specs/*` の確定済み仕様を勝手に変更しない。
5. The implementation shall logout flow の既存要件を account deletion のために再設計しない。
6. The implementation shall 実装が大きくなる場合、追加子 Issue へ分割する。

### NFR 3: Safety and UX

1. The confirmation shall destructive action と cancel action を視覚的に明確に区別する。
2. The confirmation shall 誤操作防止を優先し、退会実行前に cancel できる状態を必ず提供する。
3. The account sheet shall Dynamic Type で delete action / confirmation text / progress / error が重ならない layout を保つ。
4. The account sheet shall light / dark appearance で既存 `FeedmanTheme` または DesignSystem semantic style に沿う。
5. The account sheet shall tappable controls に実用的な hit area を持たせる。
6. The implementation shall destructive action の文言、色、role を既存 DesignSystem の danger 表現または SwiftUI の destructive role に合わせる。

## 実装境界

- 想定領域は `Feedman/Features/Account/` を中心とする。
- API 呼び出し境界や credential clear / session transition の既存抽象が `Feedman/Core/` にある場合は、必要最小限の拡張のみ許容する。
- テストは `FeedmanTests/` に追加する想定とし、実ネットワークや実 Keychain に依存しない。
- #48 で作成された account sheet / current user loading は活用し、退会 flow 以外の表示仕様を変更しない。
- #49 で作成された logout flow / session clear 境界がある場合は再利用できる。ただし `DELETE /api/users/me` 成功後に追加 revoke / logout API 成功を必須化しない。

## 確認事項

- `DELETE /api/users/me` の成功 response が 204 No Content 固定か、任意の 2xx JSON もあり得るかは `design/SPEC-iOS.md` / `design/SERVER.md` に明文化されていない。実装では APIClient の no-content 対応を前提にしつつ、既存サーバー実装の実 response を確認する必要がある。
- 退会確認の具体 UI 形状は未確定である。SwiftUI `.alert` の destructive action で足りるか、既存 DesignSystem の confirmation sheet を使うかは実装時に既存 UI パターンへ合わせる。
- 認証喪失エラー時に、account deletion failure として account sheet に留めるか、既存 session loss 方針で login へ遷移するかは既存 AppEnvironment の挙動に合わせる必要がある。ただし削除成功として扱ってはならない。
- 退会成功後に一時的な完了 toast を表示するかどうかは未確定である。login 画面へ戻すことが必須で、toast は追加必須ではない。
