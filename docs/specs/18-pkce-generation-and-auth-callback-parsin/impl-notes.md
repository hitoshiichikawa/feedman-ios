# 実装メモ

## 実装概要

- `docs/specs/18-pkce-generation-and-auth-callback-parsin/requirements.md` に Issue #18 の要件を定義した。
- `Feedman/Core/Auth/PKCE.swift` を追加し、RFC 7636 の verifier length 43...128、unreserved characters、S256 challenge 生成を実装した。
- verifier 生成は `SecRandomCopyBytes` を使い、alphabet size に対する modulo bias を避けるため rejection sampling で文字を選択する。
- challenge 生成は `CryptoKit.SHA256` と padding なし Base64URL encoding を使う。
- `Feedman/Core/Auth/AuthCallbackParser.swift` を追加し、`feedman://auth/callback?auth_code=...` から decoded `auth_code` を抽出する parser を実装した。
- parser は wrong scheme、wrong host/path、missing/empty `auth_code` を domain error として拒否し、unrelated query parameters は無視する。
- ASWebAuthenticationSession UI、login URL builder、token exchange、Keychain、APIClient refresh には触れていない。

## 変更ファイル

- `Feedman/Core/Auth/PKCE.swift`
- `Feedman/Core/Auth/AuthCallbackParser.swift`
- `FeedmanTests/PKCETests.swift`
- `FeedmanTests/AuthCallbackParserTests.swift`
- `Feedman.xcodeproj/project.pbxproj`
- `docs/specs/18-pkce-generation-and-auth-callback-parsin/requirements.md`
- `docs/specs/18-pkce-generation-and-auth-callback-parsin/impl-notes.md`

## テスト観点

- `PKCETests`:
  - default verifier が 128 文字であること。
  - generated verifier が RFC 7636 unreserved characters のみを含むこと。
  - minimum length 43 の verifier を生成できること。
  - RFC 7636 Appendix B の verifier/challenge pair で S256 Base64URL encoding が一致すること。
  - challenge に `=` padding、`+`、`/` が含まれないこと。
  - 43 未満 / 128 超過 length と invalid character を拒否すること。
- `AuthCallbackParserTests`:
  - valid callback URL から `auth_code` を抽出すること。
  - percent-encoded `auth_code` を decoded value として返すこと。
  - unrelated query parameters を無視すること。
  - wrong scheme、wrong host、wrong path、missing/empty `auth_code` を拒否すること。

## 検証

- `git diff --check` で差分の空白エラーがないことを確認した。
- `openssl` で RFC 7636 Appendix B の known verifier から expected challenge を再計算し、`E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM` と一致することを確認した。
- この Linux 環境には `swiftc` が無く、Swift の parse/build は実行できなかった。
- この Linux 環境には `xcodebuild` が無く、以下の XCTest は実行できなかった。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- この Linux 環境には `plutil` が無く、`project.pbxproj` の lint は実行できなかった。

## 確認事項

- `feedman://auth/callback` 以外の Universal Links callback URL は仕様上「or」と記載されているが、Issue #18 の期待する挙動は custom scheme parsing に限定されているため、今回の実装対象外とした。
- `/auth/google/login` URL に `code_challenge_method=S256` を付けるかはサーバー仕様に明記されていないため、今回の実装では challenge 生成だけを提供し、login URL builder は後続 Issue に委ねる。
