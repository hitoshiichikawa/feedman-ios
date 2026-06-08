# 要件定義

## 概要

Issue #14 は Parent: #2 の子 Issue として、後続の Repository 実装が同じ API 契約を前提に進められる状態を作る。
本要件では `design/SPEC-iOS.md` と `design/SERVER.md` の API 契約を優先し、Swift の API response/request structs と代表 JSON fixtures を定義対象とする。
API の日付文字列は RFC3339 `String` として保持し、favicon 系フィールドは `null` または `data:` URL を失わず扱える必要がある。
Issue コメントで人間が回答済みの追加決定事項はなく、コメントにある edit_paths は `Feedman/` と `FeedmanTests/` である。

## 要件

### Requirement 1: API domain models

**Objective:** As a Repository 実装者, I want API response/request structs が仕様どおり利用できる, so that 後続の Repository と ViewModel が画面ごとに JSON 契約を再定義しないで済む

#### Acceptance Criteria

1. The API domain models shall `design/SPEC-iOS.md` と `design/SERVER.md` の API 契約を優先し、prototype や mock data の JSON 形を正本として扱わない。
2. The API domain models shall `ItemSummary`、`ItemDetail`、`ItemSearchHit`、`Subscription`、カーソルページネーション response、Feed 登録 request/response、購読設定 request、記事状態更新 request、ユーザー response、認証 token 交換 response/request のうち、この Issue で fixtures または後続 Repository から参照される v1 API 型を表現する。
3. The API domain models shall 日付系 API フィールドを decode 時に `Date` へ自動変換せず、RFC3339 の文字列として保持する。
4. The API domain models shall `feed_favicon_url` と `favicon_url` を nullable な文字列として表現する。
5. The API domain models shall `ItemSearchHit` を `ItemSummary` とは別の型として扱い、`published_at` と `favicon_url` の null を表現できる。
6. The API domain models shall `ItemSearchHit` に `hatebu_fetched_at` を要求しない。
7. The API domain models shall ページネーション response の `items`、`next_cursor`、`has_more` を表現し、横断新着 response では `since_time` の RFC3339 文字列を表現する。
8. The API domain models shall サーバーエラー body の `error.code`、`error.message`、`error.category`、`error.action`、`error.details` を表現する。

### Requirement 2: Representative JSON fixtures

**Objective:** As a テスト作成者, I want 代表 JSON fixtures が API 契約の edge condition を含んでいる, so that decode regression を Repository 実装前に検出できる

#### Acceptance Criteria

1. When `ItemSummary` sample JSON is decoded, the API domain models shall nullable favicon fields と RFC3339 strings を失わず保持する。
2. When `Subscription` sample JSON is decoded, the API domain models shall feed status と unread count を表現する。
3. When `ItemSearchHit` sample JSON is decoded, the API domain models shall nullable `published_at` と `favicon_url` により decode が失敗しない。
4. When paginated sample JSON is decoded, the API domain models shall `items`、`next_cursor`、`has_more` を表現する。
5. When cross-feed sample JSON is decoded, the API domain models shall `since_time` を RFC3339 文字列として保持する。
6. When Feedman error sample JSON is decoded, the API domain models shall `details.retry_after_seconds` のような追加情報を失わず参照できる。
7. The JSON fixtures shall 実 token、Secret、個人情報を含まない代表値のみを使用する。

### Requirement 3: Decode test coverage

**Objective:** As a QA/Developer, I want fixtures に対する decode テスト観点が明確である, so that Linux では Xcode build ができない制約下でも macOS/Xcode で検証すべき内容がぶれない

#### Acceptance Criteria

1. When fixture decode tests are run in macOS/Xcode, the test suite shall `ItemSummary` の nullable favicon fields と RFC3339 strings の保持を検証する。
2. When fixture decode tests are run in macOS/Xcode, the test suite shall `Subscription` の feed status と unread count の decode を検証する。
3. When fixture decode tests are run in macOS/Xcode, the test suite shall `ItemSearchHit` の nullable `published_at` と `favicon_url` で decode が失敗しないことを検証する。
4. When fixture decode tests are run in macOS/Xcode, the test suite shall ページネーション response の `has_more=false` と `next_cursor=null` を decode できることを検証する。
5. When fixture decode tests are run in macOS/Xcode, the test suite shall Feedman error body の typed decode を検証する。
6. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The API domain models shall iOS 16+ のアプリで利用できる Swift `Codable` 型として表現できる。
2. The API domain models shall API の snake_case JSON keys を仕様どおり decode/encode できる。
3. The JSON fixtures shall 後続 Repository tests から再利用できる場所に配置される。

### NFR 2: Scope control

1. The implementation shall API response/request structs と representative JSON fixtures の追加に作業範囲を閉じる。
2. The implementation shall `docs/specs/*` の確定済み設計を実装 PR で勝手に変更しない。

## スコープ外

- APIClient networking の実装。
- 401 refresh hook、自動 refresh、auth refresh flow の実装。
- auth refresh の成功/失敗/再試行に関する振る舞いの定義。
- Repository protocol / real repository / mock repository の実装。
- Feature screens、ViewModel、SwiftUI 画面の実装。
- favicon `data:` URL を画像表示する UI component の実装。
- feed-scoped search UI、キーワードプッシュ通知、OPML、オフライン全文 cache。

## 実装境界

- 対象は API 契約を表す Swift の response/request structs と、代表 JSON fixtures、および fixture decode の単体テスト観点に限定する。
- API 型は `Feedman/Core` 配下、fixtures は `FeedmanTests/Fixtures` などテスト側に集約する。
- 実ネットワーク、実 Keychain、実 OAuth、実サーバーへの接続に依存する検証はこの Issue では扱わない。

## 確認事項

- `Subscription` の feed status の許容値と、status に付随する message/error reason の正確なフィールド名は `design/SPEC-iOS.md` 上では詳細型が再掲されていないため、実装時にサーバー実装または追加仕様で確認する。
- `ItemDetail`、Feed 登録 response、ユーザー情報 response など、Issue #14 の必須 fixtures に含めない v1 API 型の最小対象範囲は、後続 Issue との分担を超えない範囲で確認する。
