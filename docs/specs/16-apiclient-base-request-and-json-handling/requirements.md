# 要件定義

## 概要

Issue #16 は Parent: #2 の子 Issue として、後続の Repository 実装が共通利用できる薄い `APIClient` を定義する。
`design/SPEC-iOS.md` では iOS のネットワーク層を `URLSession + Codable` とし、すべて JSON、認証必須エンドポイントは `Authorization: Bearer <access_token>`、`baseURL` は環境ごとに切り替えるとされている。
Issue #14 で API domain models と Feedman error body が定義され、Issue #15 で `APIResponseDecoder` が 2xx success body decode と非 2xx Feedman error mapping を担う境界として追加済みである。
本 Issue はそれらを前提に、base request 構築、認証/未認証 request の切り替え、JSON body encode、JSON response decode、HTTP failure mapping の呼び出しを扱う。

Issue コメントでは追加の仕様決定事項はなく、edit_paths は `Feedman/`、`FeedmanTests/`、`Feedman.xcodeproj` とされている。

## 要件

### Requirement 1: Base URL and environment configuration

**Objective:** As a Repository 実装者, I want APIClient が環境ごとの `baseURL` から endpoint URL を解決する, so that Debug/Release やテストで接続先を差し替えても Repository 側の endpoint 定義を重複させずに済む

#### Acceptance Criteria

1. The APIClient shall 初期化時に設定された `baseURL` を保持し、各 request の相対 path をその `baseURL` に対して解決する。
2. When `baseURL` differs by environment, the APIClient shall 同じ endpoint path から環境ごとに異なる absolute URL を生成する。
3. When endpoint path begins with `/`, the APIClient shall `baseURL` の trailing slash 有無に依存せず、`/api/items/cross-feed` のような仕様上の path を壊さず解決する。
4. When endpoint path includes query items, the APIClient shall query value を URL encode し、空白、`|`、日本語などを含む検索語でも不正な URL を生成しない。
5. The APIClient shall `design/SPEC-iOS.md` と `design/SERVER.md` の endpoint path を正本として扱い、prototype や mock data の URL 形を正本として扱わない。

### Requirement 2: Authenticated and unauthenticated request construction

**Objective:** As an AuthRepository / FeedRepository 実装者, I want 認証付き/未認証の request を同じ APIClient で作れる, so that token exchange と認証必須 API が同じ JSON handling を共有できる

#### Acceptance Criteria

1. When a request is marked authenticated and an access token is supplied, the APIClient shall `Authorization: Bearer <access_token>` header を付与する。
2. When a request is marked unauthenticated, the APIClient shall `Authorization` header を付与しない。
3. The APIClient shall `Accept: application/json` を JSON endpoint の request に付与する。
4. When a request has an Encodable JSON body, the APIClient shall `Content-Type: application/json` を付与し、body を JSON encode する。
5. When a request has no body, the APIClient shall 不要な JSON body を送信しない。
6. The APIClient shall HTTP method を呼び出し側が指定でき、GET、POST、PUT、DELETE を v1 API で利用できる形にする。
7. The APIClient shall View や ViewModel が直接 `URLSession`、Bearer token header、JSONEncoder/JSONDecoder の詳細を扱わない境界を提供する。

### Requirement 3: JSON success decode

**Objective:** As a Repository 実装者, I want APIClient が success response を指定型へ decode する, so that Repository は endpoint ごとの response model を受け取るだけで済む

#### Acceptance Criteria

1. When the server returns a 2xx response with valid JSON, the APIClient shall response body を呼び出し側が指定した `Decodable` 型へ decode して返す。
2. When the response type is an Issue #14 API domain model such as `CrossFeedItemsResponse`, `CursorPaginatedResponse<ItemSummary>`, `ItemDetail`, `Subscription`, or `AuthTokenResponse`, the APIClient shall RFC3339 date strings と nullable favicon strings を `Date` 変換や data URL 変換なしで保持する。
3. When a 2xx response body cannot be decoded as the expected success type, the APIClient shall Feedman error body と混同せず、Issue #15 の `successDecodingFailed` 相当の typed error として surface する。
4. The APIClient shall success decode に `APIResponseDecoder` の既存 boundary を利用する、または同等の typed error contract を破壊しない。

### Requirement 4: HTTP failure mapping

**Objective:** As a ViewModel 実装者, I want APIClient 経由の HTTP failure が typed app error として返る, so that UI は status code、Feedman error code、message、action を検査できる

#### Acceptance Criteria

1. When the server returns a non-2xx response with valid Feedman error JSON, the APIClient shall Issue #15 の `FeedmanAPIError.feedmanError` 相当として HTTP status code と decoded Feedman error body を surface する。
2. When the server returns `429 / FEED_COOLDOWN`, the APIClient shall `details.retry_after_seconds` と `Retry-After` header を失わず surface する。
3. When the server returns a non-2xx response with malformed or non-JSON body, the APIClient shall crash せず Issue #15 の `malformedErrorResponse` 相当として status code、raw body、underlying decode error を debugging 可能な範囲で保持する。
4. The APIClient shall HTTP failure mapping を endpoint ごとの文言や UI 表示に変換しない。

### Requirement 5: URLSession transport boundary

**Objective:** As a QA/Developer, I want APIClient の transport が差し替え可能である, so that 実ネットワークに依存せず request 構築と decode/error handling をテストできる

#### Acceptance Criteria

1. The APIClient shall `URLSession` の async API を使う、または同等の async transport protocol を通じて `Data` と `URLResponse` を受け取る。
2. When the transport returns a non-HTTP `URLResponse`, the APIClient shall crash せず transport error として surface する。
3. When the transport throws a network error, the APIClient shall 元の error を失わず APIClient の typed error surface から参照できる形にする。
4. The APIClient shall unit tests で mock transport を注入でき、実サーバー、実 OAuth、実 Keychain に依存しない検証を可能にする。

### Requirement 6: Test coverage

**Objective:** As a QA/Developer, I want APIClient の request construction と JSON handling が単体テストで固定される, so that 後続 Repository 実装で共通 network contract が崩れない

#### Acceptance Criteria

1. When an unauthenticated GET request is built for a relative path, the test suite shall configured `baseURL` に対する absolute URL と `Accept: application/json` を検証する。
2. When an authenticated request is built with an access token, the test suite shall `Authorization: Bearer <token>` が付与されることを検証する。
3. When a JSON body request is built, the test suite shall `Content-Type: application/json` と encoded request body を検証する。
4. When the mock transport returns 2xx valid JSON, the test suite shall APIClient が指定された `Decodable` 型を返すことを検証する。
5. When the mock transport returns non-2xx Feedman error JSON, the test suite shall APIClient が typed Feedman error を throw し、status code、code、message、category、action を検証する。
6. When the mock transport returns `429 / FEED_COOLDOWN` with `Retry-After`, the test suite shall retry metadata が失われないことを検証する。
7. When the mock transport returns malformed error JSON or non-HTTP response, the test suite shall crash せず typed failure として扱われることを検証する。
8. When baseURL is changed between test cases, the test suite shall 同じ endpoint path が異なる absolute URL に解決されることを検証する。
9. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The APIClient shall iOS 16+ で利用できる Swift Concurrency、`URLSession`、`Codable` ベースの実装として表現できる。
2. The APIClient shall `Feedman/Core` 配下に置き、Feature View や ViewModel から直接 transport 詳細へ依存しない構成にする。
3. The APIClient shall Issue #14 の API model と Issue #15 の typed error contract を破壊しない。
4. The APIClient shall 実 token、Secret、個人情報を test data や fixture に含めない。

### NFR 2: Scope control

1. The implementation shall reusable APIClient、request construction、JSON encode/decode、HTTP failure mapping、mockable transport、単体テストに作業範囲を閉じる。
2. The implementation shall 401 refresh retry、自動 refresh、refresh token rotation、logout 制御を実装しない。
3. The implementation shall concrete repositories、Feature ViewModel、SwiftUI 画面、SFSafariViewController、Keychain token persistence を実装しない。
4. The implementation shall `docs/specs/*` の確定済み設計を実装 PR で勝手に変更しない。

## スコープ外

- 401 refresh retry、自動 refresh、refresh 失敗時の logout、token rotation 再利用検知への対応。
- `AuthRepository`、`FeedRepository` など concrete repository の実装。
- endpoint ごとの repository method、pagination orchestration、既読/スター更新 workflow。
- Google OAuth 画面、`ASWebAuthenticationSession`、auth callback parsing、PKCE generation。
- Keychain への token 保存・読込・削除。
- UI、ViewModel、画面ごとの error message / retry UI / cooldown UI。
- サーバー側 API、middleware、error format の変更。

## 実装境界

- 対象は `Feedman/Core` 近辺の reusable APIClient と、`FeedmanTests` 側の mock transport / fixture による単体テスト観点に限定する。
- APIClient は Issue #15 の `APIResponseDecoder` を呼び出す境界として設計し、成功/失敗 decode の責務を重複実装しないことを優先する。
- 認証 token の取得元はこの Issue では固定しない。呼び出し時に access token を渡す、または後続の auth layer から注入できる形に留める。
- `baseURL` の具体値や Debug/Release の選択方法は、アプリ設定または build configuration に委ねられる。ただし APIClient 自体は任意の `baseURL` を初期化で受け取れる必要がある。

## 確認事項

- Debug/Release/Staging/Local それぞれの最終的な `baseURL` 文字列は仕様内に明記されていないため、実装時にアプリ設定または Issue コメントで確認する必要がある。
- APIClient の公開 API で access token を request ごとに渡すか、token provider protocol を注入するかは、#19 Keychain TokenStore と後続 AuthRepository の実装境界に合わせて決める必要がある。
- 204 No Content を返す endpoint の decode 表現は本 Issue の AC 候補に含まれていない。`POST /api/auth/revoke` などを APIClient で扱う時点で、空 response 用の型または専用 method を定義するか確認する必要がある。
- Query item の並び順を deterministic に固定する必要があるかは、テスト実装時に request builder の公開 API と合わせて確認する必要がある。
