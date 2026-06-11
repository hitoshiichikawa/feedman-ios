# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-11T05:31:09Z -->

## Reviewed Scope

- Branch: codex/issue-16-impl-apiclient-base-request-and-json-handling
- HEAD commit: d12731a1bbb5132bb0d63b83002384f9f069fbab
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `APIClient` が `baseURL` を保持し、`makeURL` で request path を解決している（`Feedman/Core/APIClient.swift:16`, `Feedman/Core/APIClient.swift:114`）。`testUnauthenticatedGETBuildsAbsoluteURLAndJSONAcceptHeader` で absolute URL を検証（`FeedmanTests/APIClientTests.swift:5`）。
- 1.2 — `testBaseURLCanChangeForSameEndpointPath` で同じ endpoint path が異なる `baseURL` に解決されることを検証（`FeedmanTests/APIClientTests.swift:21`）。
- 1.3 — `joinPaths` で leading/trailing slash を正規化し、テストで slash あり/なしの `baseURL` と `/api/...` path を検証（`Feedman/Core/APIClient.swift:146`, `FeedmanTests/APIClientTests.swift:21`）。
- 1.4 — `URLQueryItem` と path 内 query を `URLComponents` で encode し、空白、`|`、日本語を含む query の検証がある（`Feedman/Core/APIClient.swift:123`, `Feedman/Core/APIClient.swift:134`, `FeedmanTests/APIClientTests.swift:34`, `FeedmanTests/APIClientTests.swift:55`）。
- 1.5 — APIClient は caller から渡された仕様 path を変換する薄い境界で、prototype/mock URL への依存は差分に見当たらない（`Feedman/Core/APIClient.swift:35`）。
- 2.1 — `accessToken` 指定時に `Authorization: Bearer <token>` を設定し、テストで検証（`Feedman/Core/APIClient.swift:82`, `FeedmanTests/APIClientTests.swift:68`）。
- 2.2 — `accessToken` 未指定 request では `Authorization` を付与しないことをテストで検証（`FeedmanTests/APIClientTests.swift:15`）。
- 2.3 — request に `Accept: application/json` を設定し、テストで検証（`Feedman/Core/APIClient.swift:80`, `FeedmanTests/APIClientTests.swift:15`）。
- 2.4 — body あり request で `JSONEncoder` による encode と `Content-Type: application/json` 設定を行い、テストで body 内容を検証（`Feedman/Core/APIClient.swift:86`, `FeedmanTests/APIClientTests.swift:80`）。
- 2.5 — body なし request は `httpBody` と `Content-Type` を設定しないことをテストで検証（`FeedmanTests/APIClientTests.swift:17`）。
- 2.6 — `HTTPMethod` に `GET`、`POST`、`PUT`、`DELETE` が定義され、request 作成時に caller 指定 method を反映する（`Feedman/Core/APIClient.swift:9`, `Feedman/Core/APIClient.swift:79`）。
- 2.7 — URLSession、Bearer header、JSON encode/decode は `Feedman/Core/APIClient.swift` に集約され、View/ViewModel 変更は差分に含まれていない（`Feedman/Core/APIClient.swift:16`）。
- 3.1 — 2xx valid JSON を指定 `Decodable` 型へ decode することを `AuthTokenResponse` で検証（`Feedman/Core/APIClient.swift:111`, `FeedmanTests/APIClientTests.swift:100`）。
- 3.2 — API domain model 側で RFC3339 date strings と nullable favicon strings を `String`/`String?` として decode する既存テストがある（`FeedmanTests/APIDomainModelDecodeTests.swift:7`, `FeedmanTests/APIDomainModelDecodeTests.swift:16`, `FeedmanTests/APIDomainModelDecodeTests.swift:42`, `FeedmanTests/APIDomainModelDecodeTests.swift:53`）。APIClient は同じ `JSONDecoder` 境界を利用している（`Feedman/Core/APIError.swift:3`, `Feedman/Core/APIClient.swift:111`）。
- 3.3 — success decode 失敗は `FeedmanAPIError.successDecodingFailed` として surface され、Feedman error body と混同しない既存テストがある（`Feedman/Core/APIError.swift:15`, `FeedmanTests/APIResponseDecoderTests.swift:141`）。
- 3.4 — APIClient は response decode を `APIResponseDecoder` に委譲しており、typed error contract を重複実装していない（`Feedman/Core/APIClient.swift:21`, `Feedman/Core/APIClient.swift:111`）。
- 4.1 — non-2xx Feedman error JSON が `FeedmanAPIError.feedmanError` として status/code/message/category/action を保持することをテストで検証（`FeedmanTests/APIClientTests.swift:113`）。
- 4.2 — `429 / FEED_COOLDOWN` の `details.retry_after_seconds` と `Retry-After` header を保持することをテストで検証（`FeedmanTests/APIClientTests.swift:146`）。
- 4.3 — malformed error body が crash せず `malformedErrorResponse` として status/body/underlying error を保持することをテストで検証（`FeedmanTests/APIClientTests.swift:185`）。
- 4.4 — APIClient と APIResponseDecoder は typed error を返すのみで、endpoint ごとの文言や UI 表示への変換は差分に含まれていない（`Feedman/Core/APIError.swift:23`, `Feedman/Core/APIClient.swift:94`）。
- 5.1 — `APITransport` async protocol と `URLSession` 適合で `Data`/`URLResponse` を受け取る境界を提供（`Feedman/Core/APIClient.swift:3`, `Feedman/Core/APIClient.swift:7`）。
- 5.2 — non-HTTP `URLResponse` を `FeedmanAPIError.nonHTTPResponse` として surface し、テストで検証（`Feedman/Core/APIClient.swift:107`, `FeedmanTests/APIClientTests.swift:205`）。
- 5.3 — transport が throw した error を `FeedmanAPIError.transportFailed` の underlying error として保持し、テストで検証（`Feedman/Core/APIClient.swift:101`, `FeedmanTests/APIClientTests.swift:225`）。
- 5.4 — unit tests で `MockAPITransport` を注入し、実サーバー/OAuth/Keychain に依存しない検証になっている（`FeedmanTests/APIClientTests.swift:239`, `FeedmanTests/APIClientTests.swift:265`）。
- 6.1 — unauthenticated GET の absolute URL と `Accept` header を検証（`FeedmanTests/APIClientTests.swift:5`）。
- 6.2 — authenticated request の Bearer token header を検証（`FeedmanTests/APIClientTests.swift:68`）。
- 6.3 — JSON body request の `Content-Type` と encoded body を検証（`FeedmanTests/APIClientTests.swift:80`）。
- 6.4 — mock transport の 2xx valid JSON から指定 `Decodable` 型が返ることを検証（`FeedmanTests/APIClientTests.swift:100`）。
- 6.5 — non-2xx Feedman error JSON の typed error と status/code/message/category/action を検証（`FeedmanTests/APIClientTests.swift:113`）。
- 6.6 — `429 / FEED_COOLDOWN` の retry metadata を検証（`FeedmanTests/APIClientTests.swift:146`）。
- 6.7 — malformed error JSON と non-HTTP response が typed failure になることを検証（`FeedmanTests/APIClientTests.swift:185`, `FeedmanTests/APIClientTests.swift:205`）。
- 6.8 — baseURL 変更時の absolute URL 差し替えを検証（`FeedmanTests/APIClientTests.swift:21`）。
- 6.9 — `impl-notes.md` に Xcode/iOS Simulator 環境で XCTest が未実行であることと理由が明記されている（`docs/specs/16-apiclient-base-request-and-json-handling/impl-notes.md:28`）。
- NFR 1.1 — Swift Concurrency、`URLSession`、`Codable` ベースの実装になっている（`Feedman/Core/APIClient.swift:3`, `Feedman/Core/APIClient.swift:52`）。
- NFR 1.2 — APIClient は `Feedman/Core` 配下に置かれ、Feature View/ViewModel の差分はない（`Feedman/Core/APIClient.swift:1`）。
- NFR 1.3 — Issue #15 の `APIResponseDecoder` と `FeedmanAPIError` contract を利用・拡張しており、既存 error mapping を置き換えていない（`Feedman/Core/APIClient.swift:111`, `Feedman/Core/APIError.swift:49`）。
- NFR 1.4 — test data に実 token、Secret、個人情報は見当たらない。Bearer token は `test-access-token` のみ（`FeedmanTests/APIClientTests.swift:72`）。
- NFR 2.1 — 差分は reusable APIClient、request construction、JSON handling、transport mock、単体テストに閉じている。
- NFR 2.2 — 401 refresh retry、自動 refresh、refresh token rotation、logout 制御の実装は差分に含まれていない。
- NFR 2.3 — concrete repository、Feature ViewModel、SwiftUI 画面、SFSafariViewController、Keychain token persistence の実装は差分に含まれていない。

## Findings

なし

## Summary

`git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` を確認し、差分は `Feedman/Core`、`FeedmanTests`、`Feedman.xcodeproj`、当該 spec メモに限定されていました。`tasks.md` と `design.md` は当該 spec dir に存在しないため、tasks の `_Requirements:_` / `_Boundary:_` アノテーションとの照合は実施不能でしたが、requirements の AC・実装境界との突き合わせでは reject 対象はありません。

RESULT: approve
