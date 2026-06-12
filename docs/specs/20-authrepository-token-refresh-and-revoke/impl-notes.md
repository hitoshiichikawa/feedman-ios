# 実装メモ

## 実装内容

- `Feedman/Core/Auth/AuthRepository.swift` を追加した。
  - `AuthRepository` protocol: `exchangeAuthCode(_:codeVerifier:)` / `refreshTokens()` / `revokeAndClearCredentials(accessToken:)`。
  - `FeedmanAuthRepository`: `APIClient` + `TokenStore` を協調させる real 実装。
  - `TokenCredentials`: `design/SERVER.md` §1.3 の `{ access_token, refresh_token, token_type, expires_in }` を snake_case CodingKeys で decode する応答 model。
  - request body model (`auth_code`/`code_verifier`、`refresh_token`) は本 Issue の責務に閉じた private 型として同ファイルに置き、#14 の `APIModels.swift` は変更しない。
- exchange: `POST /api/auth/token` (Bearer なし) → 成功時に refresh token を `TokenStore.saveRefreshToken` で保存し credentials を返す。
- refresh: 保存済み refresh token を読み出して `POST /api/auth/refresh` → 成功時に rotation 済み refresh token で置き換え保存。保存 token 不在時は `AuthRepositoryError.missingRefreshToken` で request を発行しない。
- revoke: 保存済み refresh token を `POST /api/auth/revoke` (Bearer 付き) → 204 成功時に `clearCredentials()`。保存 token 不在時は request なしでローカル消去のみ (冪等ログアウト)。失敗時は消去しない (#49 の方針余地を残す)。
- `Feedman/Core/APIError.swift`: 204 No Content 対応として `APIResponseDecoder.validateNoContent(from:response:)` を追加。既存 `decode` の非 2xx error 変換を private `failureError(from:response:)` へ抽出し、両者で共有 (挙動は不変、#15 の既存テストで担保)。
- `Feedman/Core/APIClient.swift`: `sendNoContent(method:path:queryItems:body:accessToken:)` を追加。transport + 非 HTTP 検査を private `perform(_:)` へ抽出し、既存 `send` と共有。
- pbxproj へ `AuthRepository.swift` (Core/Auth group) / `AuthRepositoryTests.swift` を登録した (build/file ID 140-141/242-243)。

## 実装上の判断

- refresh 拒否 (401, server は単一 sentinel に正規化) 時は保存済み refresh token に副作用を残さない。セッション破棄・logout への昇格は #22/#23 の責務とし、本 repository は機械的な成功/失敗の境界に徹する。
- revoke の Bearer 用 access token は `String?` 引数で受け取る (access token はメモリ保持・呼び出し側責務のため)。nil の場合は Authorization header なしで送信される (`APIClient.makeRequest` の既存挙動どおり)。
- access token / expires_in のメモリ管理・期限監視は実装しない (スコープ外の明記どおり)。

## テスト

- `FeedmanTests/AuthRepositoryTests.swift` を追加した (8 tests)。mock transport (`RecordingTransport`) と mock store (`InMemoryTokenStore`) のみで、実ネットワーク・実 Keychain に接続しない。
  - exchange 成功: path/method/JSON body (snake_case)/Bearer なし + refresh token 保存 + credentials 返却。
  - exchange 失敗 (400 INVALID_GRANT): typed error surface + 保存なし。
  - refresh 成功: 保存 token の送信 + rotation 置換保存。
  - refresh 保存 token 不在: request 不発行 + `missingRefreshToken`。
  - refresh 拒否 (401 INVALID_REFRESH_TOKEN): typed error + 保存 token 不変。
  - revoke 成功 (204): Bearer header + body 検証 + `clearCredentials` 呼び出し。
  - revoke 失敗 (500): typed error + credential 保持。
  - revoke 保存 token 不在: request 不発行 + ローカル消去のみ。

## 検証

- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 17' test` (macOS / Xcode 26.0)
  - 結果: 成功。Executed 121 tests, with 0 failures (新規 8 tests を含む)。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`: OK。

## 確認事項

- 外部依存 (hitoshiichikawa/feedman#166-168) は server develop に merge 済み (`staged-for-release`) の状態で実装した。server 側が main へ promote される前に iOS 側を実機結合する場合は、接続先環境が server develop 相当であることを確認すること。
