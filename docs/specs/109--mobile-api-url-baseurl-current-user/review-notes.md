# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-23T11:33:10Z -->

## Reviewed Scope

- Branch: codex/issue-109-impl--mobile-api-url-baseurl-current-user
- HEAD commit: a9d0317ab2704be4a61c5a5dbbaf57e9d93a3089
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `AppEnvironment.production` が `resolveProductionAPIBaseURL` で明示設定 origin を解決する（`Feedman/Core/AppEnvironment.swift:267`, `Feedman/Core/AppEnvironment.swift:321`）。`testConfiguredProductionAPIBaseURLUsesEnvironmentOrigin` が環境値を検証（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:179`）。
- 1.2 — 欠落時は `missingAPIBaseURL` になり、`http://localhost:3000` default へ戻らない（`Feedman/Core/AppEnvironment.swift:338`）。`testConfiguredProductionAPIBaseURLRejectsMissingReleaseEquivalentOrigin` で検証（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:188`）。
- 1.3 — authenticated API requests 用 `APIClient` が同じ `apiBaseURL` で生成される（`Feedman/Core/AppEnvironment.swift:286`）。`testProductionEnvironmentUsesAPIClientKeywordRepository` と origin resolver test で確認（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:167`, `FeedmanTests/AppEnvironmentSessionRestoreTests.swift:179`）。
- 1.4 — native Google login の `authBaseURL` に同じ `apiBaseURL` を渡す（`Feedman/Core/AppEnvironment.swift:305`）。`testProductionEnvironmentUsesConfiguredOriginForNativeLoginBase` で検証（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:173`）。
- 1.5 — 欠落・localhost・invalid origin を developer-observable configuration failure として扱う（`Feedman/Core/AppEnvironment.swift:23`, `Feedman/Core/AppEnvironment.swift:350`, `Feedman/Core/AppEnvironment.swift:358`）。round 2 で `testConfiguredProductionAPIBaseURLRejectsInvalidOrigin` が追加され、前回の missing test は解消（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:206`）。
- 2.1 — login URL path は `/auth/google/login`、`flow=native` を生成する（`Feedman/Features/Login/LoginViewModel.swift:103`, `Feedman/Features/Login/LoginViewModel.swift:110`）。`testStartGoogleLoginBuildsNativeFlowURLAndEntersLoading` で検証（`FeedmanTests/LoginViewModelTests.swift:14`）。
- 2.2 — current PKCE challenge を `code_challenge` に設定する（`Feedman/Features/Login/LoginViewModel.swift:111`）。同 login URL test で検証（`FeedmanTests/LoginViewModelTests.swift:30`）。
- 2.3 — `code_challenge_method=S256` を設定する（`Feedman/Features/Login/LoginViewModel.swift:112`）。同 login URL test で検証（`FeedmanTests/LoginViewModelTests.swift:31`）。
- 2.4 — stale `flow` を除去し `native` に正規化する（`Feedman/Features/Login/LoginViewModel.swift:105`, `Feedman/Features/Login/LoginViewModel.swift:110`）。`testStartGoogleLoginNormalizesStaleAuthQueryParameters` で検証（`FeedmanTests/LoginViewModelTests.swift:37`）。
- 2.5 — stale `code_challenge` を current challenge に正規化する（`Feedman/Features/Login/LoginViewModel.swift:106`, `Feedman/Features/Login/LoginViewModel.swift:111`）。normalization test で検証（`FeedmanTests/LoginViewModelTests.swift:50`）。
- 2.6 — stale `code_challenge_method` を `S256` に正規化する（`Feedman/Features/Login/LoginViewModel.swift:107`, `Feedman/Features/Login/LoginViewModel.swift:112`）。normalization test で検証（`FeedmanTests/LoginViewModelTests.swift:51`）。
- 2.7 — unrelated query parameter は保持される（`Feedman/Features/Login/LoginViewModel.swift:104`）。`diagnostic=1` の保持を login URL tests が検証（`FeedmanTests/LoginViewModelTests.swift:28`, `FeedmanTests/LoginViewModelTests.swift:52`）。
- 2.8 — login flow は既存 `ASWebAuthenticationSession` 境界のままで、WebView Cookie fallback 追加は差分に無い（`Feedman/Features/Login/LoginViewModel.swift:98`, `FeedmanTests/LoginViewModelTests.swift:14`）。
- 3.1 — mobile current user は `GET /api/users/me` を使う（`Feedman/Core/AccountRepository.swift:11`）。`testCurrentUserRequestsUsersMeWithBearerToken` で検証（`FeedmanTests/AccountRepositoryTests.swift:7`）。
- 3.2 — current user request は Bearer token 付き APIClient request として送られる（`Feedman/Core/AccountRepository.swift:12`, `Feedman/Core/AccountRepository.swift:15`）。Bearer header と refresh retry を tests が検証（`FeedmanTests/AccountRepositoryTests.swift:20`, `FeedmanTests/AccountRepositoryTests.swift:27`）。
- 3.3 — `UserResponse` decode と account loading success path は既存 path を維持し、mobile current user contract fields の decode test がある（`FeedmanTests/AccountRepositoryTests.swift:87`, `docs/specs/109--mobile-api-url-baseurl-current-user/impl-notes.md:48`）。
- 3.4 — current user 取得では `/auth/me` を使わず `/api/users/me` を検証している（`Feedman/Core/AccountRepository.swift:14`, `FeedmanTests/AccountRepositoryTests.swift:21`）。
- 3.5 — account deletion は引き続き `DELETE /api/users/me` を使う（`Feedman/Core/AccountRepository.swift:19`）。`testDeleteCurrentUserRequestsUsersMeWithBearerToken` で検証（`FeedmanTests/AccountRepositoryTests.swift:59`）。
- 4.1 — README が Simulator / device testing 用 API origin 設定方法を説明する（`README.md:45`）。
- 4.2 — README が local-development origin と Release 相当 origin を区別する（`README.md:50`, `README.md:57`）。
- 4.3 — README smoke checklist が `flow=native`, `code_challenge`, `code_challenge_method=S256` を明記する（`README.md:98`）。
- 4.4 — README smoke checklist が mobile current user の `GET /api/users/me` を明記する（`README.md:108`）。
- 4.5 — README は production / staging URL を未確定値として扱い、仮 endpoint を記載していない（`README.md:57`）。
- 5.1 — login URL test が `code_challenge_method=S256` を検証する（`FeedmanTests/LoginViewModelTests.swift:31`）。
- 5.2 — stale auth query normalization test が `flow`, `code_challenge`, `code_challenge_method` の正規化を検証する（`FeedmanTests/LoginViewModelTests.swift:37`）。
- 5.3 — account repository test が current user loading path `/api/users/me` を検証する（`FeedmanTests/AccountRepositoryTests.swift:21`）。
- 5.4 — API origin configuration tests が Release-equivalent origin を `http://localhost:3000` 固定にせず、invalid origin も拒否することを検証する（`FeedmanTests/AppEnvironmentSessionRestoreTests.swift:197`, `FeedmanTests/AppEnvironmentSessionRestoreTests.swift:206`）。
- 5.5 — impl-notes に canonical `xcodebuild ... test` の round 2 実行結果として 460 tests passed が記録されている（`docs/specs/109--mobile-api-url-baseurl-current-user/impl-notes.md:16`）。

## Findings

なし

## Summary

round 1 の reject 理由だった AC 1.5 の invalid API origin テストは `testConfiguredProductionAPIBaseURLRejectsInvalidOrigin` で追加され、Developer の round 2 canonical test も green と記録されている。指定必読の `tasks.md` と `design.md` は spec ディレクトリに存在しなかったため、`_Boundary:_` アノテーションによる境界照合は実施不能だったが、確認できた差分内に 3 カテゴリの reject 理由はない。

RESULT: approve
