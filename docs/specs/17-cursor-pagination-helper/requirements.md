# 要件定義

## Issue 概要

Issue #17 は Parent: #2 の子 Issue として、記事一覧系で共通利用できる小さな cursor pagination helper を定義する。
横断タイムライン、フィード別記事一覧、スター一覧、検索結果など、`items` 配列を返す一覧 API が同じ cursor pagination 契約を使えるようにし、画面や Repository ごとにページング状態管理を重複実装しないことを目的とする。

依存 Issue #14 は PR #57 として `develop` へ merge 済みである。Issue コメントの「依存解消しているのでそのまま実行」を決定事項として扱い、本 Issue は #14 の API domain models と JSON fixtures が存在する前提で進める。

## 背景

`design/SPEC-iOS.md` は一覧 API のページネーションをカーソル方式として定義している。
次ページ要求、終端判定、refresh 開始時の状態 reset、取得済み item の蓄積は複数画面で共通する責務である。
本 Issue ではその責務を UI や endpoint 実装から切り離し、Core の小さな状態 helper として利用できる要件を定義する。

`design/SERVER.md` には cursor pagination そのものの追加契約は見当たらないため、ページング契約は `design/SPEC-iOS.md` の API 契約を正本とする。

## スコープ

- `Feedman/Core/Pagination` 近辺に配置する reusable な pagination state / helper の要件定義。
- `items`、`next_cursor`、`has_more` を持つ API response から、次回 request 用 cursor と終端状態を更新する責務。
- refresh 開始時に cursor と item accumulation state を初期化する責務。
- `FeedmanTests` 側で、終端判定、次 cursor 更新、refresh reset、item 蓄積を検証する単体テスト観点。
- Issue #14 で定義された cursor pagination response model を前提にした利用境界。

## スコープ外

- SwiftUI 画面、ViewModel、無限スクロール sentinel、Pull-to-refresh UI の実装。
- endpoint ごとの request path、query items、limit 値、filter、search scope の実装。
- Repository protocol / mock repository / real repository の実装。
- APIClient networking、自動 refresh、認証、Keychain、SFSafariViewController の実装。
- サーバー API、response schema、`design/SPEC-iOS.md`、`design/SERVER.md` の変更。
- 横断新着固有の `since_time` セッション固定ロジックの具体実装。ただし helper が `since_time` を壊さない境界は意識する。

## API 契約から読み取れる前提

- Cursor pagination response は `{ items, next_cursor: string?, has_more }` の形を持つ。
- 次ページ要求では `?cursor=<next_cursor>&limit=<n>` を使う。
- `has_more == false` の場合は終端であり、追加ページ要求を止める。
- `next_cursor` が `null` または空文字の場合も終端として扱う。
- `has_more == true` かつ非空の `next_cursor` がある場合だけ、次ページ request 用 cursor を公開できる。
- 横断新着 `GET /api/items/cross-feed` は 50件/回、上限200、`since_time` 付きであり、`since_time` はセッション初回値を固定する。ただし本 helper は endpoint 固有の `since_time` 生成・保持を担当しない。
- 全一覧で無限スクロールを行い、終端では「最後まで読みました」を表示する想定がある。ただし表示そのものは UI scope として本 Issue には含めない。

## 要件

### Requirement 1: Pagination state model

**Objective:** As a Repository / ViewModel 実装者, I want cursor pagination の現在状態を共通 helper で表現できる, so that 各一覧で cursor、終端、蓄積 items の扱いを重複させないで済む

#### Acceptance Criteria

1. The pagination helper shall 現在の蓄積 items、次回 request 用 cursor、追加ページ取得可否を表現する。
2. The pagination helper shall 初期状態で item 蓄積を空、request cursor を未指定、追加ページ取得可として扱える。
3. When a first page is applied, the pagination helper shall response の `items` を蓄積 items として保持し、`next_cursor` と `has_more` から次状態を計算する。
4. When an additional page is applied, the pagination helper shall 既存 items の後ろに response の `items` を追加する。
5. The pagination helper shall item 型に依存しない generic な構造として表現できる。

### Requirement 2: Cursor and terminal handling

**Objective:** As a Repository 実装者, I want API 契約どおりに次 cursor と終端を判定できる, so that 余分な追加 request や終端漏れを防げる

#### Acceptance Criteria

1. When `has_more` is false, the pagination helper shall 追加ページ取得不可として扱い、次回 request cursor を公開しない。
2. When `next_cursor` is null, the pagination helper shall 追加ページ取得不可として扱い、次回 request cursor を公開しない。
3. When `next_cursor` is empty, the pagination helper shall 追加ページ取得不可として扱い、次回 request cursor を公開しない。
4. When `has_more` is true and `next_cursor` is present, the pagination helper shall 次回 request cursor としてその値を公開する。
5. If `has_more` is true but `next_cursor` is null or empty, the pagination helper shall API 契約上の終端条件を優先し、追加ページ取得不可として扱う。
6. The pagination helper shall `limit` 値そのものを決定しない。`limit` は endpoint / Repository 側の request 構築責務として扱う。

### Requirement 3: Refresh reset

**Objective:** As a ViewModel 実装者, I want refresh 開始時に pagination state を安全に初期化できる, so that 古い cursor や古い items が新しい一覧取得に混ざらない

#### Acceptance Criteria

1. When refresh starts, the pagination helper shall cursor と item accumulation state を reset できる。
2. When refresh starts, the pagination helper shall 追加ページ取得可否を初期状態に戻せる。
3. When a refreshed first page is applied after reset, the pagination helper shall reset 前の items を引き継がず、refresh 後の `items` のみを蓄積する。
4. While refresh is in progress, the pagination helper shall endpoint 固有の network request 実行や UI loading 表示を担当しない。

### Requirement 4: Integration boundary

**Objective:** As a Developer, I want pagination helper の責務境界が明確である, so that Core の小さな部品として後続 Repository / ViewModel から安全に使える

#### Acceptance Criteria

1. The pagination helper shall `Feedman/Core/Pagination` 近辺に置ける独立した Core component として設計される。
2. The pagination helper shall `URLSession`、`APIClient`、Bearer token、Keychain、SwiftUI View に依存しない。
3. The pagination helper shall endpoint path、query item、filter、search query、feed id、subscription id を知る必要がない。
4. The pagination helper shall Issue #14 の cursor pagination response model、または同じ `items` / `next_cursor` / `has_more` 契約を持つ値から状態更新できる。
5. Where 横断新着 response が `since_time` を含む, the pagination helper shall `since_time` を解釈・更新せず、呼び出し側が保持する付加情報を壊さない。

### Requirement 5: Test coverage

**Objective:** As a QA/Developer, I want pagination helper の主要状態遷移が単体テストで固定される, so that 後続一覧実装で pagination logic の回帰を検出できる

#### Acceptance Criteria

1. When first page response has items, `has_more` true, and non-empty `next_cursor`, the test suite shall items が蓄積され、次 cursor が公開されることを検証する。
2. When additional page response is applied, the test suite shall 既存 items の後ろに新しい items が追加されることを検証する。
3. When response has `has_more` false, the test suite shall 追加ページ取得不可になることを検証する。
4. When response has null `next_cursor`, the test suite shall 追加ページ取得不可になることを検証する。
5. When response has empty `next_cursor`, the test suite shall 追加ページ取得不可になることを検証する。
6. When refresh reset is performed, the test suite shall cursor と蓄積 items が初期化されることを検証する。
7. When refreshed first page is applied after reset, the test suite shall reset 前の items が残らないことを検証する。
8. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The pagination helper shall iOS 16+ で利用できる Swift 実装として表現できる。
2. The pagination helper shall Swift Concurrency や UI framework に依存しない同期的な state helper として表現できる。
3. The pagination helper shall `struct` と `let` / 限定的な可変状態を優先し、呼び出し側が状態遷移を追いやすい API にする。

### NFR 2: Scope control

1. The implementation shall pagination state / helper とその単体テストに作業範囲を閉じる。
2. The implementation shall UI、endpoint、Repository、APIClient、auth、Keychain の実装を含めない。
3. The implementation shall `docs/specs/*` の確定済み設計を実装 PR で勝手に変更しない。

## Developer 向け実装境界

- 主な編集対象は `Feedman/Core/Pagination` と `FeedmanTests` とする。
- 必要に応じて Xcode project への file reference 追加は実装作業上の範囲に含められるが、PM 要件としては UI や Repository への接続を要求しない。
- helper は `ItemSummary` 専用にせず、`ItemSearchHit` や将来の一覧 item にも使える generic な境界を優先する。
- helper は request を発火しない。呼び出し側が `nextCursor` と `canLoadMore` 相当の状態を見て request 可否を判断する。
- helper は重複 item の排除を必須責務にしない。重複排除が必要な場合は endpoint / Repository / ViewModel の責務として別 Issue で扱う。
- helper は loading、error、empty 表示状態を必須責務にしない。これらは ViewModel / UI の責務として扱う。

## 確認事項

- `has_more == true` かつ `next_cursor` が `null` または空文字の場合は、`design/SPEC-iOS.md` の「`next_cursor` が null/空で終端」を優先して終端扱いとする。本要件では追加確認で止めない。
- 重複 item の排除、最大保持件数、メモリ節約のための trimming は Issue #17 の本文・仕様に明記がないため、本 Issue の必須要件には含めない。
- loading / in-flight guard を helper に含めるかは実装判断の余地がある。ただし本要件では network request の多重実行制御を UI / ViewModel / Repository 側の責務として扱い、Core helper の必須 scope には含めない。
