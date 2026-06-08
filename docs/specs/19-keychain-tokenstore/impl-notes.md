# Issue #19 Keychain TokenStore 実装ノート

## 実装内容

- `Feedman/Core/Auth/TokenStore.swift` を追加した。
- `TokenStore` protocol を定義し、refresh token の保存、読み込み、credential clear を抽象化した。
- `KeychainTokenStore` を追加し、`kSecClassGenericPassword`、`kSecAttrAccessibleAfterFirstUnlock` で refresh token を Keychain に保存する実装にした。
- `KeychainClient` / `SystemKeychainClient` を追加し、Unit test では実 Keychain に依存せず OSStatus と保存データを制御できるようにした。
- Keychain 失敗は `TokenStoreError.keychainError(operation:status:)` として `OSStatus` を保持して surface する。
- 保存済み token への再保存では `errSecDuplicateItem` を update に変換し、最新 token で上書きする。
- `clearCredentials()` は未保存状態の `errSecItemNotFound` を成功扱いにした。

## テスト

- `FeedmanTests/TokenStoreTests.swift` を追加した。
- fake Keychain client により以下を検証する。
  - 未保存時の load は nil
  - save 後に同じ refresh token を load できる
  - Keychain accessibility に `afterFirstUnlock` を指定する
  - 既存 token を新 token で上書きできる
  - clear 後の load は nil
  - clear は未保存状態でも成功する
  - add / copyMatching / update / delete の Keychain 失敗が typed error になる
  - UTF-8 として decode できない保存データは typed error になる

## 検証結果

- `git diff --check` は成功。
- この Linux 環境には `xcodebuild` が存在しないため、Xcode test は未実行。
- macOS/Xcode 環境では以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 確認事項

- Keychain service/account の仕様上の固定値は未定義のため、`KeychainTokenStore` の default service は `Bundle.main.bundleIdentifier` に `.auth.refresh-token` を付けた値とした。明示指定も可能にしている。
- Access group は Issue #19 の範囲外として未指定。
