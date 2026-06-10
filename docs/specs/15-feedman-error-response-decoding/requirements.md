# 要件定義

## 概要

Issue #15 は Parent: #2 の子 Issue として、サーバーが返す Feedman 標準エラー body を API layer で decode し、Repository や UI が検査可能な typed app error として扱える状態を作る。
`design/SPEC-iOS.md` と `design/SERVER.md` では、エラー body は `{ error: { code, message, category, action, details? } }` と定義され、`429 / FEED_COOLDOWN` では `details.retry_after_seconds` と `Retry-After` ヘッダが返る。
Issue #14 では API domain model として `FeedmanErrorResponse` / `FeedmanErrorBody` / `JSONValue` 相当の型が対象化されているため、本 Issue はそれらの契約を利用し、HTTP error response から typed app error へ変換する責務に閉じる。

Issue コメントでは #14 依存により一度ブロックされた履歴があり、edit_paths は `Feedman/` と `FeedmanTests/` とされている。

## 要件

### Requirement 1: Feedman error body decoding

**Objective:** As a Repository 実装者, I want サーバー標準エラー body を typed app error として受け取れる, so that Repository と ViewModel が HTTP response body を個別に parse せずにユーザー表示や分岐へ利用できる

#### Acceptance Criteria

1. When the server returns `{ error: { code, message, category, action, details } }`, the API layer shall `code`、`message`、`category`、`action`、`details` を失わず decode する。
2. When the server returns an error body without `details`, the API layer shall `details` が存在しない error として decode し、必須フィールドの decode を継続する。
3. When the server returns `details` containing JSON primitives, arrays, objects, or null values, the API layer shall typed app error からそれらの値を検査できる形で保持する。
4. The API layer shall `design/SPEC-iOS.md` と `design/SERVER.md` の Feedman 標準エラー形式を正本として扱い、prototype や mock data のエラー形を正本として扱わない。

### Requirement 2: App error surface

**Objective:** As a ViewModel 実装者, I want API 失敗時の原因が typed app error として分類される, so that UI state は表示可能な message と機械判定用の code/action を同じ source から参照できる

#### Acceptance Criteria

1. When an HTTP response has a non-success status code and a valid Feedman error body, the API layer shall typed app error として HTTP status code と decoded Feedman error body を surface する。
2. When the decoded Feedman error body contains `message`, the typed app error shall UI 表示候補としてその message を参照できる。
3. When the decoded Feedman error body contains `code`, `category`, or `action`, the typed app error shall Repository / ViewModel が文字列として検査できる形で保持する。
4. If `category` または `action` の既知値一覧が仕様で確定していない, the implementation shall unknown value で decode が失敗しない表現を使う。

### Requirement 3: FEED_COOLDOWN details preservation

**Objective:** As a Repository 実装者, I want `FEED_COOLDOWN` の retry metadata を失わず受け取れる, so that 後続 Issue が cooldown 表示や制御を実装する際に API response を再解釈しなくて済む

#### Acceptance Criteria

1. When the server returns `code = "FEED_COOLDOWN"` and `details.retry_after_seconds`, the API layer shall `retry_after_seconds` の数値を typed app error から参照できる形で保持する。
2. When the server returns `Retry-After` header with a Feedman error response, the API layer shall header value を失わず参照できる形で保持する、または typed transport metadata から参照できる境界を定義する。
3. The API layer shall `FEED_COOLDOWN` の retry metadata を保持するだけに留め、再試行実行、待機制御、通知、UI 表示タイミングをこの Issue で実装しない。

### Requirement 4: Malformed error handling

**Objective:** As a QA/Developer, I want malformed error body でも API layer がクラッシュしない, so that サーバー障害や契約外 response が user-facing failure として安全に扱われる

#### Acceptance Criteria

1. When an HTTP response has a non-success status code but the body is not valid JSON, the API layer shall crash せず transport/decoding error として surface する。
2. When an HTTP response has a non-success status code and the JSON body lacks required Feedman error fields, the API layer shall crash せず malformed error body として扱う。
3. When an HTTP response has a success status code but the expected success body fails to decode, the API layer shall Feedman error body と混同せず success response decode failure として surface する。
4. The API layer shall malformed error body の fallback message を実装する場合でも、元の HTTP status code と decode failure の情報を debugging 可能な範囲で保持する。

### Requirement 5: Test coverage

**Objective:** As a QA/Developer, I want error decode の正常系と異常系が単体テストで固定される, so that 後続 Repository 実装で error handling の契約が崩れない

#### Acceptance Criteria

1. When a valid Feedman error fixture is decoded, the test suite shall `code`、`message`、`category`、`action`、`details` を検証する。
2. When a `FEED_COOLDOWN` fixture with `details.retry_after_seconds` is decoded, the test suite shall retry seconds を typed app error から参照できることを検証する。
3. When a Feedman error fixture omits optional `details`, the test suite shall decode が成功し `details` が未設定として扱われることを検証する。
4. When a malformed error body fixture is handled, the test suite shall crash せず transport/decoding error として surface されることを検証する。
5. When error response handling tests are run in macOS/Xcode, the test suite shall 実ネットワークへ接続せず fixture または mock response で検証する。
6. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The API layer shall iOS 16+ で利用できる Swift Concurrency / `Codable` ベースの実装として表現できる。
2. The typed app error shall Repository と ViewModel が Swift の型として inspect でき、View が直接 `URLSession` response body を parse しない構成にする。
3. The implementation shall 実 token、Secret、個人情報を fixture や test data に含めない。

### NFR 2: Scope control

1. The implementation shall Feedman 標準エラー response の decode と typed app error surface に作業範囲を閉じる。
2. The implementation shall Issue #14 で定義済みの API model 契約を勝手に拡張・破壊しない。
3. The implementation shall endpoint-specific behavior をこの Issue に含めない。

## スコープ外

- Retry UI、cooldown banner、toast、alert、その他のユーザー通知 UI。
- 自動 retry、manual retry、backoff、待機タイマーなどの retry behavior。
- endpoint ごとの個別エラー分岐、個別文言、個別 recovery action。
- 401 refresh hook、自動 refresh、auth refresh flow、refresh 失敗時の logout 制御。
- Repository protocol / real repository / mock repository の各 feature 別エラー設計。
- サーバー側 `WriteErrorResponse` の変更。
- Feedman 標準エラー形式以外の API 契約追加。

## 実装境界

- 対象は `Feedman/Core` 近辺の API layer error decode と、`FeedmanTests` 側の fixture/mock response による単体テスト観点に限定する。
- `FeedmanErrorResponse` / `FeedmanErrorBody` / `JSONValue` 相当の API model は Issue #14 の成果物を前提にし、この Issue では HTTP error response から app error へ surface する境界を定義する。
- ViewModel / SwiftUI 画面は typed app error を受け取れる前提だけを置き、この Issue では画面ごとの表示仕様を定義しない。

## 確認事項

- typed app error の具体的な型名と配置先は、既存 APIClient の実装状況に合わせて実装時に決める必要がある。
- `category` と `action` の許容値一覧は `design/SPEC-iOS.md` / `design/SERVER.md` に列挙されていないため、enum 化する場合は unknown value の扱いを確認する必要がある。
- `Retry-After` header を typed app error 本体に含めるか、HTTP metadata として別に保持するかは既存 API layer の境界に合わせて決める必要がある。
