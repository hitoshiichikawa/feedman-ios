# 独立レビュー notes

## Summary

- 対象: Issue #19 `Keychain TokenStore`
- 対象 HEAD: `690f059464873d4d6551a4622e7bc6bb94384301`
- Base: `develop`
- Round: 1 / 最大 2 round
- 差分取得:
  - `git diff --stat develop..HEAD`: 5 files changed, 442 insertions(+)
  - `git log --oneline develop..HEAD`: `690f059 feat: add keychain token store`
- 指定された必読ファイルのうち、`docs/specs/19-keychain-tokenstore/tasks.md` は存在しなかった。したがって `_Requirements:_` / `_Boundary:_` annotation は参照不能で、判定は `requirements.md`、`impl-notes.md`、該当差分に基づく。
- `docs/specs/19-keychain-tokenstore/design.md` は存在しなかった。
- `requirements.md` には numeric ID が付与されていないため、AC 対応は受入基準の記載順で確認した。
- Linux 環境のため `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は実行できなかった。`xcodebuild` / `swiftc` / `swift` もこの環境には存在しなかった。
- `git diff --check develop..HEAD` は問題なし。

## Review Scope

判定カテゴリは依頼どおり `AC 未カバー` / `missing test` / `boundary 逸脱` のみに限定した。スタイル、命名、lint、フォーマットのみの指摘は行っていない。

## AC Coverage

- AC 1: When `KeychainTokenStore.saveRefreshToken(_:)` is called with a token, `loadRefreshToken()` shall return the same token.
  - `Feedman/Core/Auth/TokenStore.swift:62` で UTF-8 data を `kSecClassGenericPassword` item として保存し、`Feedman/Core/Auth/TokenStore.swift:80` で Keychain data を `String` に戻している。
  - `FeedmanTests/TokenStoreTests.swift:15` の `testSavePersistsRefreshTokenForLaterLoad` で検証されている。
- AC 2: When `KeychainTokenStore.clearCredentials()` is called after saving a token, `loadRefreshToken()` shall return nil.
  - `Feedman/Core/Auth/TokenStore.swift:102` で base query に一致する credential を削除し、`errSecItemNotFound` は成功扱いにしている。
  - `FeedmanTests/TokenStoreTests.swift:44` の `testClearCredentialsRemovesRefreshToken` で検証されている。
- AC 3: When the Keychain backend reports a failure status, TokenStore shall surface a typed error that preserves the underlying `OSStatus`.
  - `Feedman/Core/Auth/TokenStore.swift:17` の `TokenStoreError.keychainError(operation:status:)` が `OSStatus` を保持する typed error になっている。
  - `FeedmanTests/TokenStoreTests.swift:63`、`:74`、`:85`、`:97` で add / copyMatching / update / delete の失敗が typed error になることを検証している。
- AC 4: When an existing token is saved again, `loadRefreshToken()` shall return the newest token.
  - `Feedman/Core/Auth/TokenStore.swift:73` で `errSecDuplicateItem` を update に変換し、`Feedman/Core/Auth/TokenStore.swift:113` で最新 data を更新している。
  - `FeedmanTests/TokenStoreTests.swift:34` の `testSaveOverwritesExistingRefreshToken` で検証されている。
- AC 5: Unit tests shall cover save/load, overwrite, clear, missing token, Keychain failure, and invalid UTF-8 stored data without requiring real device Keychain state.
  - `FeedmanTests/TokenStoreTests.swift:141` の `FakeKeychainClient` により実 Keychain state に依存しない境界でテストされている。
  - save/load は `FeedmanTests/TokenStoreTests.swift:15`、overwrite は `:34`、clear は `:44`、missing token は `:6`、Keychain failure は `:63`、`:74`、`:85`、`:97`、invalid UTF-8 は `:108` で検証されている。

## NFR / Boundary

- `TokenStore` protocol は `Feedman/Core/Auth/TokenStore.swift:4` に定義され、mock/real 差し替え可能な境界として `KeychainClient` も `Feedman/Core/Auth/TokenStore.swift:22` に分離されている。
- Keychain backing implementation は `Feedman/Core/Auth/TokenStore.swift:126` で `kSecClassGenericPassword` を使っている。
- Keychain accessibility は保存時 `Feedman/Core/Auth/TokenStore.swift:65`、更新時 `Feedman/Core/Auth/TokenStore.swift:115` で `kSecAttrAccessibleAfterFirstUnlock` を指定している。
- 差分は `Feedman/Core/Auth/TokenStore.swift`、`FeedmanTests/TokenStoreTests.swift`、Xcode project 登録、Issue spec notes に閉じており、Network refresh flow、APIClient、AuthRepository、UI、access token 永続化、revoke API 呼び出しへの拡張は見当たらない。

## Findings

該当なし。

RESULT: approve
