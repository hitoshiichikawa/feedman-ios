# Issue #19 Keychain TokenStore 要件定義

## 背景

Epic #3 の Google ログイン/トークン認証を小さく実装するため、refresh token の永続化責務を `TokenStore` として分離する。`design/SPEC-iOS.md` では refresh token のみを Keychain に永続化し、access token はメモリ上の短命値として扱う方針が定義されている。`design/SERVER.md` では `/api/auth/token` と `/api/auth/refresh` が refresh token を発行/ローテーションし、ログアウト時に revoke へ渡すことが定義されている。

Issue コメントには Path Overlap Checker の edit path と処理開始通知のみがあり、人間による追加決定事項はない。

## スコープ

- `Feedman/Core/Auth` に refresh token を保存、読み込み、削除できる `TokenStore` abstraction を追加する。
- Keychain backing implementation は `kSecClassGenericPassword` を使う。
- Keychain item accessibility は仕様どおり `kSecAttrAccessibleAfterFirstUnlock` とする。
- refresh token は UTF-8 文字列として保存し、load 時に `String` として返す。
- Keychain 失敗は呼び出し側が分岐可能な typed error として surface する。
- Unit test では実 Keychain 依存を避け、Keychain 操作を差し替えられる境界で save/load/clear/error を検証する。

## スコープ外

- Network refresh flow、`APIClient` の 401 retry、`AuthRepository` 全体の実装。
- Google login UI、`ASWebAuthenticationSession`、PKCE exchange flow の統合。
- access token の永続化。
- refresh token revoke API 呼び出し。
- Keychain access group、iCloud Keychain 同期、biometric access control。

## 機能要件

- When a refresh token is saved, the app shall persist it in Keychain so it can be loaded after process restart or app relaunch.
- When a refresh token is loaded and no token exists, the TokenStore shall return nil.
- When credentials are cleared, subsequent loads shall return nil.
- When saving a refresh token over an existing token, the TokenStore shall replace the stored value with the latest token.
- When Keychain returns an unexpected OSStatus, the TokenStore shall throw a typed `TokenStoreError`.
- When Keychain returns duplicate item during save, the TokenStore shall update the existing item instead of surfacing duplicate as a terminal failure.
- When stored Keychain data cannot be decoded as UTF-8, the TokenStore shall throw a typed decoding error.

## 非機能要件

- `TokenStore` は protocol として定義し、将来の mock/real 差し替えを可能にする。
- View は Keychain に直接触らない前提を維持する。
- 実装は Issue #19 の責務に閉じ、AuthRepository/APIClient/UI へ広げない。
- Swift identifier、型名、ファイル名は英語にする。
- docs 配下の記述は日本語にし、EARS keyword は英語固定にする。

## 受入基準

- When `KeychainTokenStore.saveRefreshToken(_:)` is called with a token, `loadRefreshToken()` shall return the same token.
- When `KeychainTokenStore.clearCredentials()` is called after saving a token, `loadRefreshToken()` shall return nil.
- When the Keychain backend reports a failure status, TokenStore shall surface a typed error that preserves the underlying `OSStatus`.
- When an existing token is saved again, `loadRefreshToken()` shall return the newest token.
- Unit tests shall cover save/load, overwrite, clear, missing token, Keychain failure, and invalid UTF-8 stored data without requiring real device Keychain state.

## 確認事項

- Keychain `service` / `account` の具体名は既存仕様にないため、実装内のデフォルト値として安定した bundle-oriented 名を置く。
- Access group は指定しない。共有 Keychain が必要になった場合は別 Issue で扱う。
