# 要件定義

## 概要

Issue #20 は Parent: #3 の子 Issue として、auth code の本トークン交換・access token の refresh (rotation 対応)・refresh token の revoke を行い、`TokenStore` を更新する `AuthRepository` を実装する。

API 契約は `design/SERVER.md` §1.3 を正本とする:

- `POST /api/auth/token`: `{ auth_code, code_verifier }` → 200 `{ access_token, refresh_token, token_type, expires_in }` / 400 `INVALID_GRANT`
- `POST /api/auth/refresh`: `{ refresh_token }` → 200 同形 (refresh token は rotation 済みの新値) / 401 `INVALID_REFRESH_TOKEN`
- `POST /api/auth/revoke`: `{ refresh_token }` → 204 No Content (Bearer 認証下)

サーバー実装 (hitoshiichikawa/feedman#166/#167/#168, server develop へ merge 済み) では、refresh の拒否は token 不存在・期限切れ・失効・rotation 済みを区別しない単一の 401 に正規化されている。また `design/SPEC-iOS.md` §3 のとおり、永続化するのは `refresh_token` のみで `access_token` はメモリ保持 (呼び出し側責務) とする。

依存する既存成果物: `APIClient` / `APIResponseDecoder` (#15/#16)、`TokenStore` protocol と `KeychainTokenStore` (#19)、PKCE / callback parser (#18)。

## 要件

### Requirement 1: Auth code の本トークン交換

**Objective:** As a ログイン画面実装者 (#21), I want auth code と PKCE verifier を渡すだけで本トークンが得られ refresh token が保存される, so that 画面側は Keychain や API 契約の詳細を扱わずに済む

#### Acceptance Criteria

1. When token exchange is requested, the repository shall `POST /api/auth/token` へ `{ auth_code, code_verifier }` を JSON body で送信する。
2. When token exchange succeeds, the repository shall 応答の refresh token を `TokenStore` へ保存し、取得した credentials (access token / refresh token / token_type / expires_in) を呼び出し側へ返す。
3. When token exchange fails, the repository shall typed app error (#15 の `FeedmanAPIError`) を surface し、`TokenStore` を変更しない。
4. The repository shall token exchange request に Bearer header を付与しない (未認証エンドポイント)。

### Requirement 2: Refresh rotation

**Objective:** As a 401 retry hook 実装者 (#23), I want 保存済み refresh token から新しい access token を再発行できる, so that 透過 refresh を repository 境界の単一呼び出しで実現できる

#### Acceptance Criteria

1. When refresh is requested, the repository shall `TokenStore` から保存済み refresh token を読み出し、`POST /api/auth/refresh` へ `{ refresh_token }` を送信する。
2. When refresh succeeds, the rotated refresh token shall 旧 token を置き換えて `TokenStore` へ保存され、新 credentials が返される。
3. If no refresh token is stored, the repository shall ネットワーク request を発行せず typed error で失敗する。
4. When the server rejects the refresh (401), the repository shall typed app error を surface し、保存済み refresh token を変更しない (セッション破棄の判断は #22/#23 の責務)。

### Requirement 3: Revoke と credential clear

**Objective:** As a ログアウト実装者 (#49), I want revoke の成功時にローカル credential が消えている, so that ログアウト後の端末に有効な refresh token が残らない

#### Acceptance Criteria

1. When revoke is requested with a stored refresh token, the repository shall `POST /api/auth/revoke` へ `{ refresh_token }` を Bearer header 付きで送信する。
2. When revoke succeeds (204 No Content), the repository shall `TokenStore.clearCredentials()` でローカル credential を消去する。
3. When revoke fails, the repository shall typed app error を surface し、ローカル credential を消去しない (失敗時のログアウト方針は #49 の責務)。
4. If no refresh token is stored, the repository shall ネットワーク request を発行せずローカル credential の消去のみ行う (冪等なログアウト)。

### Requirement 4: API 基盤の 204 対応

**Objective:** As a Core API 実装者, I want 204 No Content 応答を扱える送信境界, so that revoke のような body なし成功応答でも decode 失敗にならない

#### Acceptance Criteria

1. When a request expecting no content receives a 2xx response, the API layer shall body を decode せず成功として扱う。
2. When a request expecting no content receives a non-2xx response, the API layer shall #15 と同一の error 変換 (Feedman error envelope → `feedmanError`、malformed → `malformedErrorResponse`) を適用する。
3. The implementation shall #15 の既存 `decode` の挙動 (成功 decode / エラー変換) を変更しない。

### Requirement 5: テストカバレッジ

**Objective:** As a QA/Developer, I want exchange / refresh / revoke の成功・失敗と TokenStore 副作用が単体テストで固定される, so that 後続の #21/#22/#23/#49 が repository 契約に依存できる

#### Acceptance Criteria

1. When auth repository tests are run, the test suite shall mock transport と mock TokenStore を使い、実ネットワーク・実 Keychain へ接続しない。
2. When exchange / refresh / revoke の各成功パスが検証される, the test suite shall request の path・method・JSON body (snake_case)・Bearer header 有無と、TokenStore への副作用 (保存 / rotation 置換 / clear) を検証する。
3. When 失敗パスが検証される, the test suite shall typed error の surface と TokenStore が変更されないことを検証する。
4. When refresh token 不在の分岐が検証される, the test suite shall request が発行されないことを検証する。

## 非機能要件

### NFR 1: Compatibility

1. The repository shall protocol を先に定義し、mock と real implementation を差し替え可能にする (AGENTS.md 方針)。
2. The repository shall Swift Concurrency (`async`/`await`) ベースで iOS 16+ で動作する。
3. The implementation shall 実 token・Secret を fixture に含めない。

### NFR 2: Scope control

1. The implementation shall ASWebAuthenticationSession の presentation・ログイン画面 UI (#21) を含めない。
2. The implementation shall 起動時 session 復元 (#22)、APIClient の 401 自動 retry hook (#23)、ログアウト UI フロー (#49) を含めない。
3. The implementation shall #14/#15/#16/#19 の既存契約を破壊しない (追加のみ)。
4. The implementation shall access token のメモリ保持・有効期限管理を行わない (呼び出し側責務)。

## スコープ外

- ASWebAuthenticationSession によるログイン UI、認可フロー開始、callback 受領 (#21)。
- 起動時の auth 復元と session state 管理 (#22)。
- APIClient の 401 検知 → 自動 refresh → retry の透過処理 (#23)。
- ログアウト確認 UI と revoke 失敗時のユーザー向け文言・方針 (#49)。
- access token の保存 (仕様上メモリ保持のため Keychain へ保存しない)。

## 実装境界

- 追加対象: `Feedman/Core/Auth/AuthRepository.swift` (protocol + real 実装 + request/response model)、`FeedmanTests/AuthRepositoryTests.swift`、`APIClient` / `APIResponseDecoder` への 204 対応の最小追加、pbxproj への登録。
- request/response model は本 Issue の責務に閉じた型として `Core/Auth` 配下に置き、#14 の `APIModels.swift` は変更しない。

## 確認事項

- revoke の Bearer 用 access token は呼び出し側 (メモリ保持者) から引数で受け取る。`design/SERVER.md` は revoke を Bearer 認証下と定義しているため、引数は省略可能とせず明示的に受け取る形とする (nil 許容にする場合も header 省略の挙動を明確にする)。
- refresh 拒否 (401) 時に保存済み token を消すかは #22/#23 のセッション方針に委ね、本 Issue では副作用なしとする。
