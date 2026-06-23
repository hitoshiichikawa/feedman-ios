# Issue #109 mobile API auth URL and current user contract タスク分割

- [x] 1. API origin configuration を Release 相当 runtime 向けに補正する
  - `AppEnvironment.production()` が明示 API origin、環境変数、Info.plist 設定を解決できるようにする。
  - missing / invalid / localhost origin を developer-observable configuration failure として扱う。
  - authenticated API request と native login base URL に同じ resolved origin を渡す。
  - API origin configuration の回帰 XCTest を追加する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 5.4_
  - _Boundary: APIOriginConfiguration, RegressionCoverage_

- [x] 2. Native Google login URL contract を mobile API 契約へ合わせる
  - `/auth/google/login` に `flow=native`、current `code_challenge`、`code_challenge_method=S256` を設定する。
  - stale `flow` / `code_challenge` / `code_challenge_method` を current mobile contract へ正規化する。
  - unrelated query parameters を保持し、WebView Cookie fallback を追加しない。
  - login URL の回帰 XCTest を追加する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 5.1, 5.2_
  - _Boundary: NativeGoogleLoginURLBuilder, RegressionCoverage_

- [x] 3. Mobile current user endpoint を `GET /api/users/me` へ補正する
  - `FeedmanAccountRepository.currentUser(accessToken:)` を Bearer token 付き `GET /api/users/me` request にする。
  - account loading success path と `UserResponse` decode を既存 flow に接続したまま維持する。
  - current user loading が `/auth/me` を使わないこと、account deletion が `DELETE /api/users/me` のままであることを XCTest で固定する。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 5.3_
  - _Boundary: MobileAccountRepository, RegressionCoverage_

- [x] 4. README と smoke checklist を mobile API 契約へ合わせる
  - Simulator / device testing の API origin 設定を記載する。
  - local-development origin と Release 相当 origin の違いを明記する。
  - native Google login smoke checklist に `flow=native`、`code_challenge`、`code_challenge_method=S256` を含める。
  - account smoke checklist に mobile current user loading の `GET /api/users/me` を含める。
  - 未確定の production / staging / signing / OAuth client / secret 値を発明しない。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - _Boundary: DeveloperDocumentation_

- [x] 5. Final verification と traceability を記録する
  - canonical `xcodebuild ... test` を macOS/Xcode 環境で実行し、結果を `impl-notes.md` に記録する。
  - AC Coverage Matrix で requirements、implementation path、production entrypoint、test assertion、verification result を対応付ける。
  - `npm test` / `npm run lint` / `npm run build` が iOS Xcode project では対象外であることを記録する。
  - _Requirements: 5.5_
  - _Boundary: RegressionCoverage_
