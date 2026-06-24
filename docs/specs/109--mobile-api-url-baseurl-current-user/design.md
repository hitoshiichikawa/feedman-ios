# Issue #109 mobile API auth URL and current user contract 設計

## 概要

Issue #109 では、iOS アプリの API origin 解決、native Google login URL、mobile current user endpoint を Android / iOS 共通の v1 mobile API 契約へ合わせる。対象は `Feedman/Core/AppEnvironment.swift`、`Feedman/Features/Login/LoginViewModel.swift`、`Feedman/Core/AccountRepository.swift`、`README.md`、および対応する XCTest である。

本設計は、Release 相当 runtime で `http://localhost:3000` に暗黙 fallback しないこと、native OAuth URL に `flow=native` と PKCE S256 query を含めること、mobile current user を Bearer token 付き `GET /api/users/me` として扱うことを固定する。

## 目的

- Release 相当 runtime の API origin を明示設定に限定し、未設定・不正値を developer-observable failure にする。
- authenticated API request と native Google login URL が同じ configured API origin を使う。
- native Google login URL で stale query を mobile contract に正規化する。
- Account feature の current user loading を `GET /api/users/me` に揃え、account deletion の `DELETE /api/users/me` は維持する。
- README と XCTest で Simulator / device 検証、mobile auth contract、current user contract の回帰を確認できるようにする。

## 非目的

- production / staging の正式 URL、OAuth client ID、signing、secret 値の決定。
- サーバーリポジトリ側の `hitoshiichikawa/feedman#207` 実装。
- token / refresh / revoke endpoint の契約変更。
- Universal Links callback への切り替え。
- WebView Cookie login fallback の追加。
- v1 スコープ外機能の smoke checklist 追加。

## 現状

- `AppEnvironment.production()` は Release 相当 runtime の API base URL を構築する入口である。
- `LoginViewModel.startGoogleLogin()` は PKCE challenge を生成し、`makeGoogleLoginURL(codeChallenge:)` で `/auth/google/login` URL を構築する。
- `FeedmanAccountRepository.currentUser(accessToken:)` は account loading の repository 境界であり、Bearer token API request を `APIClient` に委譲する。
- `FeedmanAccountRepository.deleteCurrentUser(accessToken:)` は既に `DELETE /api/users/me` を使用する。
- README は developer が Simulator / device / Release 相当接続先を確認する主要な smoke checklist である。

## 設計方針

### 1. API origin configuration

`AppEnvironment.production(apiBaseURL:)` は、明示引数、`FEEDMAN_API_BASE_URL`、`Info.plist` の `FeedmanAPIBaseURL` の順に API origin を解決する。未設定、空文字、未解決 build setting placeholder、不正 URL、path / query / fragment / userinfo を含む URL、`localhost`、または local loopback 以外の HTTP origin は production origin として拒否する。

Unit test host の app bootstrap は Release 相当 runtime ではないため、テスト実行中の missing configuration だけ `127.0.0.1` fallback を限定的に許容する。この fallback は production app launch の設定契約としては扱わない。

### 2. Native Google login URL contract

`LoginViewModel.makeGoogleLoginURL(codeChallenge:)` は configured auth base URL の origin を維持し、path を `/auth/google/login` に正規化する。既存 query のうち `flow`、`code_challenge`、`code_challenge_method` は mobile contract と衝突するため破棄し、現在の login attempt の値で再追加する。その他の query は診断用などの非衝突値として保持する。

WebView Cookie login fallback は追加せず、既存の `ASWebAuthenticationSession` ベースの native token auth flow を維持する。

### 3. Mobile current user contract

`FeedmanAccountRepository.currentUser(accessToken:)` は `APIClient.send(_:path:accessToken:)` に `GET /api/users/me` 相当の path と access token を渡す。`GET /auth/me` は web Cookie 用 endpoint として残し、mobile current user loading では使わない。

Account deletion は既存 contract の `DELETE /api/users/me` を維持し、current user path 変更の巻き添えで削除 endpoint を変えない。

### 4. Documentation and smoke checklist

README は Simulator / device の local-development origin と Release 相当 origin を分けて説明する。native Google login smoke test では `flow=native`、`code_challenge`、`code_challenge_method=S256` を確認項目に含め、account smoke test では `GET /api/users/me` を明記する。

未確定の production / staging URL、OAuth client、signing、secret は値を発明せず、authoritative source 不在として扱う。

## Components

| Component | Files | Responsibility |
|-----------|-------|----------------|
| APIOriginConfiguration | `Feedman/Core/AppEnvironment.swift`, `Feedman/Info.plist` | Release 相当 API origin の解決、検証、production environment への注入 |
| NativeGoogleLoginURLBuilder | `Feedman/Features/Login/LoginViewModel.swift` | `/auth/google/login` URL と mobile OAuth query の正規化 |
| MobileAccountRepository | `Feedman/Core/AccountRepository.swift` | Bearer token 付き current user / account deletion endpoint の repository 境界 |
| DeveloperDocumentation | `README.md` | API origin 設定、native auth、current user smoke checklist の説明 |
| RegressionCoverage | `FeedmanTests/*` | API origin、login URL、current user endpoint の XCTest 回帰固定 |

## AC Coverage

| Requirement / AC | Design component | Design decision |
|------------------|------------------|-----------------|
| 1.1 | APIOriginConfiguration | Release 相当 runtime は明示設定 origin を使い、localhost 固定 default を持たない |
| 1.2 | APIOriginConfiguration | explicit local-development override が無い Release 相当設定では localhost に silent fallback しない |
| 1.3 | APIOriginConfiguration | resolved origin を `APIClient` に注入し authenticated request の base にする |
| 1.4 | APIOriginConfiguration / NativeGoogleLoginURLBuilder | resolved origin を `authBaseURL` として login URL construction に渡す |
| 1.5 | APIOriginConfiguration | missing / invalid origin は configuration error または launch-time failure として観測可能にする |
| 2.1 | NativeGoogleLoginURLBuilder | login URL path を `/auth/google/login`、query `flow=native` に正規化する |
| 2.2 | NativeGoogleLoginURLBuilder | current PKCE challenge を `code_challenge` として追加する |
| 2.3 | NativeGoogleLoginURLBuilder | `code_challenge_method=S256` を追加する |
| 2.4 | NativeGoogleLoginURLBuilder | stale `flow` query は破棄して `native` に置換する |
| 2.5 | NativeGoogleLoginURLBuilder | stale `code_challenge` query は current challenge に置換する |
| 2.6 | NativeGoogleLoginURLBuilder | stale `code_challenge_method` query は `S256` に置換する |
| 2.7 | NativeGoogleLoginURLBuilder | contract と衝突しない query は保持する |
| 2.8 | NativeGoogleLoginURLBuilder | WebView Cookie fallback は追加せず native auth flow を維持する |
| 3.1 | MobileAccountRepository | current user loading は `GET /api/users/me` を使う |
| 3.2 | MobileAccountRepository | current user request は access token を `APIClient` に渡す authenticated request とする |
| 3.3 | MobileAccountRepository | `UserResponse` decode と既存 account success path に接続する |
| 3.4 | MobileAccountRepository | mobile current user loading で `/auth/me` を使わない |
| 3.5 | MobileAccountRepository | account deletion は `DELETE /api/users/me` を維持する |
| 4.1 | DeveloperDocumentation | README に Simulator / device testing の API origin 設定を記載する |
| 4.2 | DeveloperDocumentation | local-development origin と Release 相当 origin の違いを明記する |
| 4.3 | DeveloperDocumentation | login smoke checklist に `flow=native`、`code_challenge`、`code_challenge_method=S256` を含める |
| 4.4 | DeveloperDocumentation | account smoke checklist に `GET /api/users/me` を含める |
| 4.5 | DeveloperDocumentation | 未確定の production / staging / signing / OAuth / secret 値は発明しない |
| 5.1 | RegressionCoverage | login URL XCTest で `code_challenge_method=S256` を検証する |
| 5.2 | RegressionCoverage | stale auth query 正規化を XCTest で検証する |
| 5.3 | RegressionCoverage | account repository XCTest で `/api/users/me` を検証する |
| 5.4 | RegressionCoverage | API origin XCTest で Release 相当 origin が localhost 固定でないことを検証する |
| 5.5 | RegressionCoverage | macOS/Xcode で canonical `xcodebuild ... test` を実行し、結果を `impl-notes.md` に記録する |

## リスクと対策

| Risk | Mitigation |
|------|------------|
| Release 相当 origin 未設定で app launch が失敗する | developer-observable failure と README の設定手順で明示し、localhost への silent fallback を避ける |
| `Info.plist` placeholder が未解決のまま URL として扱われる | placeholder prefix を missing configuration として扱う |
| stale auth query が mobile contract を壊す | conflict key を破棄して current login attempt の値を再追加する |
| `/auth/me` と `/api/users/me` の用途が混同される | mobile repository と spec / README で `/api/users/me` を明記し、web Cookie endpoint は再定義しない |

## Verify

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
