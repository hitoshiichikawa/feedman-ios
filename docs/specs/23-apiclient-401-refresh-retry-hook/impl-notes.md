# 実装メモ

## 実装内容

- `Feedman/Core/APIClient.swift`
  - `APIClient.AccessTokenRefreshHook` (`@Sendable () async throws -> String`) を追加した。
  - 認証付き request が初回 `401` を受けた場合のみ refresh hook を呼び、返却された access token で `Authorization: Bearer <token>` を差し替えて元 request を 1 回だけ retry する。
  - retry 後の `401` は再 refresh せず、`FeedmanAPIError.authRequired` として surface する。
  - refresh hook 未設定、または refresh hook 失敗時も `FeedmanAPIError.authRequired` として surface する。
  - request の method / URL / query / body / Authorization 以外の headers は `URLRequest` をコピーして retry することで保持する。
- `Feedman/Core/APIError.swift`
  - `FeedmanAPIError.authRequired(AuthRequiredContext)` を追加した。
  - `AuthRequiredReason` は `missingRefreshHook` / `refreshFailed` / `retryUnauthorized`。
  - `APIResponseDecoder` の既存 non-2xx 変換を `error(from:response:)` として再利用可能にし、auth-required の underlying context に既存 typed error を保持できるようにした。
- `FeedmanTests/APIClientTests.swift`
  - 401 refresh 成功時の retry、refresh hook 呼び出し回数、新 access token header、decoded response を検証するテストを追加した。
  - refresh hook 未設定、refresh 失敗、retry 後 401、未認証 request の 401、認証付き non-401 error の分岐を追加した。
  - 並列 401 で同一 `APIClient` インスタンス内の in-flight refresh を共有し、refresh hook が 1 回だけ呼ばれることを検証するテストを追加した。

## 実装上の判断

- refresh token rotation、TokenStore 更新、credential clear は #20 の `AuthRepository` 責務に残し、`APIClient` は refresh hook が返す access token だけを使う。
- app 側は refresh hook として `AuthRepository.refreshTokens().accessToken` を返す closure を注入する想定。
- #20 の `FeedmanAuthRepository.refreshTokens()` 単体には並列 refresh 抑止がないため、本 Issue では `APIClient` 内の `AccessTokenRefreshCoordinator` actor で in-flight refresh を共有する。
- retry 対象は method で制限しない。初回 `401` では server 側 business action が実行されていない前提で、要件どおり POST/PUT も 1 回だけ retry する。
- refresh 失敗時の credential clear は行わない。セッション破棄や login 画面遷移は呼び出し側の責務として扱う。

## テスト

- 追加・更新: `FeedmanTests/APIClientTests.swift`
  - `testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken`
  - `testAuthenticated401WithoutRefreshHookSurfacesAuthRequired`
  - `testRefreshFailureSurfacesAuthRequiredWithoutRetry`
  - `testRetried401SurfacesAuthRequiredWithoutSecondRefresh`
  - `testUnauthenticated401DoesNotRefreshAndSurfacesFeedmanError`
  - `testAuthenticatedNon401ErrorDoesNotRefreshAndPreservesFeedmanError`
  - `testConcurrentAuthenticated401SharesInFlightRefresh`

## 検証

- 実行不可: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、Xcode.app が存在しないため `xcodebuild` が実行できない。
- 実行: `swiftc -typecheck -parse-as-library Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Auth/AuthRepository.swift Feedman/Core/Auth/TokenStore.swift`
  - 結果: 成功。
- 実行: `swiftc -parse FeedmanTests/APIClientTests.swift`
  - 結果: 成功。
- 試行: 一時 `Feedman` module を作成して `FeedmanTests/APIClientTests.swift` の typecheck。
  - 結果: CommandLineTools 環境に `XCTest` module が無く、`no such module 'XCTest'` で不可。

## 確認事項

- Xcode.app が利用可能な macOS 環境で full XCTest を再実行する必要がある。
