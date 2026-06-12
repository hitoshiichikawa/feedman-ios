# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-12T06:31:12Z -->

## Reviewed Scope

- Branch: codex/issue-23-impl-apiclient-401-refresh-retry-hook
- HEAD commit: fbe9afc68bd9dd4190d00ad3c9c6f682044f7a80
- Compared to: develop..HEAD

## 確認した差分/ファイル

- `git diff --stat develop..HEAD` / `git log --oneline develop..HEAD` を確認。`develop..HEAD` には #20 の merge commit `773874a` と #23 commit `fbe9afc` が含まれる。
- #23 commit 単体では `Feedman/Core/APIClient.swift`, `Feedman/Core/APIError.swift`, `FeedmanTests/APIClientTests.swift`, `docs/specs/23-apiclient-401-refresh-retry-hook/requirements.md`, `docs/specs/23-apiclient-401-refresh-retry-hook/impl-notes.md` が変更対象。
- `tasks.md` と `design.md` は `docs/specs/23-apiclient-401-refresh-retry-hook/` に存在しないため、tasks の `_Requirements:_` / `_Boundary:_` アノテーション照合は実施不可。境界は `requirements.md` のスコープ/実装境界/NFR で照合した。
- `xcodebuild -version` は active developer directory が CommandLineTools のため失敗。補助確認として `swiftc -typecheck -parse-as-library Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Auth/AuthRepository.swift Feedman/Core/Auth/TokenStore.swift` は成功。

## Verified Requirements

- 1.1 — `performWithRefreshRetry` が初回 response を受け、`shouldRefresh` で authenticated 401 のみ refresh 候補にする（`Feedman/Core/APIClient.swift:128`, `Feedman/Core/APIClient.swift:156`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で検証。
- 1.2 — Authorization なしの 401 は refresh せず、既存 decoder 経路で `FeedmanAPIError.feedmanError` を返す（`Feedman/Core/APIClient.swift:156`, `Feedman/Core/APIError.swift:34`）。`testUnauthenticated401DoesNotRefreshAndSurfacesFeedmanError` で検証。
- 1.3 — non-401 non-2xx は refresh せず response を返し、decode 時に既存 typed error mapping へ流れる（`Feedman/Core/APIClient.swift:130`, `Feedman/Core/APIClient.swift:125`）。`testAuthenticatedNon401ErrorDoesNotRefreshAndPreservesFeedmanError` で検証。
- 1.4 — 2xx response は `shouldRefresh` が false になり refresh されない（`Feedman/Core/APIClient.swift:128`, `Feedman/Core/APIClient.swift:156`）。既存 success decode tests と refresh 分岐条件で確認。
- 1.5 — success decode と non-refreshable failure mapping は `APIResponseDecoder.decode` / `error(from:response:)` に委譲される（`Feedman/Core/APIError.swift:10`, `Feedman/Core/APIError.swift:34`）。
- 2.1 — authenticated 401 で configured hook を 1 回呼ぶ（`Feedman/Core/APIClient.swift:134`, `Feedman/Core/APIClient.swift:178`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で call count 1 を検証。
- 2.2 — retry 後 401 でも refresh を再実行せず `authRequired(.retryUnauthorized)` を返す（`Feedman/Core/APIClient.swift:142`）。`testRetried401SurfacesAuthRequiredWithoutSecondRefresh` で検証。
- 2.3 — hook 未設定時は crash/retry せず `authRequired(.missingRefreshHook)` を返す（`Feedman/Core/APIClient.swift:168`）。`testAuthenticated401WithoutRefreshHookSurfacesAuthRequired` で検証。
- 2.4 — hook 戻り値を retry request の `Authorization: Bearer <token>` に反映する（`Feedman/Core/APIClient.swift:134`, `Feedman/Core/APIClient.swift:140`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で検証。
- 2.5 / 2.6 — APIClient は closure hook の access token だけを受け取り、Keychain や `/api/auth/refresh` を直接扱わない（`Feedman/Core/APIClient.swift:17`, `Feedman/Core/APIClient.swift:178`）。refresh token rotation は #20 `AuthRepository` 側の責務に残る。
- 3.1 — refresh 成功後に元 `URLRequest` を 1 回 retry する（`Feedman/Core/APIClient.swift:139`, `Feedman/Core/APIClient.swift:142`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で endpoint request 2 回を検証。
- 3.2 — retry は `var retryRequest = request` で元 request をコピーし、Authorization のみ差し替えるため method/path/query/body/headers を保持する（`Feedman/Core/APIClient.swift:139`, `Feedman/Core/APIClient.swift:140`）。
- 3.3 — retry 後 2xx valid JSON は元 requested `Decodable` 型として decode される（`Feedman/Core/APIClient.swift:124`, `Feedman/Core/APIClient.swift:125`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で decoded response を検証。
- 3.4 — retry 後 non-2xx は再 refresh せず、401 以外は existing typed error mapping に流れる（`Feedman/Core/APIClient.swift:142`, `Feedman/Core/APIClient.swift:153`, `Feedman/Core/APIError.swift:23`）。
- 3.5 — retry 後 401 は `FeedmanAPIError.authRequired(.retryUnauthorized)` として通常 endpoint error と区別でき、無限 retry しない（`Feedman/Core/APIClient.swift:143`）。`testRetried401SurfacesAuthRequiredWithoutSecondRefresh` で検証。
- 3.6 — refresh と retry が成功した場合、初回 401 は caller に露出せず retry response が返る（`Feedman/Core/APIClient.swift:134`, `Feedman/Core/APIClient.swift:153`）。`testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` で検証。
- 4.1 / 4.2 — refresh hook failure は `authRequired(.refreshFailed)` に変換され、元 request は retry されない（`Feedman/Core/APIClient.swift:178`, `Feedman/Core/APIClient.swift:181`）。`testRefreshFailureSurfacesAuthRequiredWithoutRetry` で検証。
- 4.3 — refresh hook の transport/malformed 等の failure は `underlyingError` として保持される（`Feedman/Core/APIClient.swift:185`）。
- 4.4 — APIClient 内に credential clear 処理は追加されていない。clear は #20 `AuthRepository.revokeAndClearCredentials` 側の責務（`Feedman/Core/APIClient.swift:16`, `Feedman/Core/Auth/AuthRepository.swift:69`）。
- 4.5 — `FeedmanAPIError.authRequired` が `feedmanError` とは別 case として追加されている（`Feedman/Core/APIError.swift:59`）。refresh failure / retry 401 tests で検証。
- 4.6 — error context に token 文字列を保存・log する差分は見当たらない（`Feedman/Core/APIError.swift:95`）。
- 5.1 / 5.2 / 5.3 — `AccessTokenRefreshCoordinator` actor が in-flight refresh task を共有し、後続 request は同一 task を await して retry する（`Feedman/Core/APIClient.swift:257`）。`testConcurrentAuthenticated401SharesInFlightRefresh` で hook 1 回、retry 2 回を検証。
- 5.4 — shared refresh failure は coordinator の同一 task error が各 caller に伝播し、`refreshAccessToken` で `authRequired(.refreshFailed)` に変換される（`Feedman/Core/APIClient.swift:260`, `Feedman/Core/APIClient.swift:180`）。
- 5.5 / 5.6 — #20 `FeedmanAuthRepository.refreshTokens()` 単体に duplicate suppression がないため APIClient 側 coordinator で実装したことが `impl-notes.md` に明記されている。
- 6.1 — unauthenticated request は引き続き `accessToken` なしで送れる（`Feedman/Core/APIClient.swift:42`）。既存 APIClient tests と unauthenticated 401 test で確認。
- 6.2 — explicit access token request は維持され、refresh hook の戻り access token で retry できる（`Feedman/Core/APIClient.swift:47`, `Feedman/Core/APIClient.swift:140`）。
- 6.3 — `APITransport` 注入は維持され、tests は mock transport を使用している（`Feedman/Core/APIClient.swift:3`, `FeedmanTests/APIClientTests.swift:498`）。
- 6.4 — SwiftUI View/ViewModel が URLSession/Keychain/refresh storage に依存する差分はない。
- 6.5 — request body は `makeRequest` 時点で `Data` に encode 済みで、retry は同じ `URLRequest` をコピーする（`Feedman/Core/APIClient.swift:112`, `Feedman/Core/APIClient.swift:139`）。
- 6.6 — #23 commit 単体の実装差分は `Feedman/Core` と `FeedmanTests`、当該 spec notes に限定。`develop..HEAD` に見える #20 ファイルは dependency merge commit 由来で、requirements の依存 mismatch 明記対象として扱った。
- 7.1 / 7.2 / 7.3 — `testAuthenticated401RefreshesOnceAndRetriesWithNewBearerToken` が endpoint request 2 回、refresh hook 1 回、refreshed bearer、decoded response を検証。
- 7.4 — `testRefreshFailureSurfacesAuthRequiredWithoutRetry` が retry 不実行と auth-required typed error を検証。
- 7.5 — `testRetried401SurfacesAuthRequiredWithoutSecondRefresh` が retry 後 401 で refresh 2 回目なしを検証。
- 7.6 — `testUnauthenticated401DoesNotRefreshAndSurfacesFeedmanError` が unauthenticated 401 で refresh なしを検証。
- 7.7 — `testAuthenticatedNon401ErrorDoesNotRefreshAndPreservesFeedmanError` が 429/FEED_COOLDOWN の metadata 維持と refresh なしを検証。
- 7.8 — `testConcurrentAuthenticated401SharesInFlightRefresh` が APIClient 側 duplicate refresh suppression を検証。
- 7.9 — 追加 tests は `MockAPITransport` / mock refresh hook を使い、実 network/OAuth/Keychain/real token に依存していない。
- 7.10 — Developer は `impl-notes.md` で Xcode.app 不在により指定 `xcodebuild` を実行できなかった理由を報告している。Reviewer 側でも同じ理由で `xcodebuild -version` が失敗した。
- NFR 1.1〜1.5 — iOS 16 / Swift 5 project 設定のまま Swift Concurrency を使用し、#16/#20 境界を保持。実 token/secret/個人情報は見当たらない。
- NFR 2.1〜2.5 — #23 commit は 401 refresh retry hook と focused unit tests に限定され、UI・server contract・PR/release 操作の差分はない。

## Findings

なし

## Summary

AC 未カバー、missing test、boundary 逸脱はいずれも検出しなかった。`develop..HEAD` に #20 merge commit が含まれるが、#23 要件側で #20 依存 mismatch として明記されている範囲であり、#23 commit 単体の実装差分は APIClient refresh retry hook とそのテストに閉じている。

RESULT: approve
