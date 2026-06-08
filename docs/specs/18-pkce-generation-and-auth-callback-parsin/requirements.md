# 要件定義

## 概要

Issue #18 は Parent: #3 の子 Issue として、Google ログインの native token auth フローで使う PKCE verifier/challenge 生成と、OAuth 完了後の `feedman://auth/callback` URL parsing を実装する。
本要件では `design/SPEC-iOS.md` と `design/SERVER.md` の認証契約を優先し、ASWebAuthenticationSession UI、token exchange、Keychain 保存、APIClient refresh 処理は対象外とする。
Issue コメントで人間が回答済みの追加決定事項はなく、コメントにある edit_paths は `Feedman/` と `FeedmanTests/` である。

## 要件

### Requirement 1: PKCE verifier generation

**Objective:** As an Auth 実装者, I want RFC 7636 に準拠した code verifier を生成できる, so that native OAuth flow でサーバー側 PKCE 検証に必要な `code_verifier` を安全に保持できる

#### Acceptance Criteria

1. When a verifier is generated, the generated verifier shall be 43 文字以上 128 文字以下である。
2. When a verifier is generated, the generated verifier shall RFC 7636 の unreserved characters（`A-Z`、`a-z`、`0-9`、`-`、`.`、`_`、`~`）のみを含む。
3. When a verifier is generated with default settings, the generated verifier shall be 128 文字として扱える。
4. When verifier generation needs entropy, the implementation shall 暗号学的に安全な乱数 source を使い、実 token、Secret、個人情報を含まない。
5. If a verifier length outside 43...128 is requested, the generator shall fail with a domain error instead of silently producing a non-compliant verifier.

### Requirement 2: PKCE S256 challenge generation

**Objective:** As an Auth 実装者, I want verifier から S256 code challenge を生成できる, so that `/auth/google/login?flow=native&code_challenge=...` に仕様どおり渡せる

#### Acceptance Criteria

1. When a challenge is generated, the challenge shall be `BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))` である。
2. When a challenge is generated, the challenge shall not include `=` padding。
3. When a challenge is generated, the challenge shall not include standard Base64 の `+` または `/`。
4. When a challenge is generated from an invalid verifier, the generator shall fail with a domain error instead of accepting values that violate PKCE length/character requirements.
5. The implementation shall use S256 only; `plain` method support is out of scope.

### Requirement 3: Auth callback parsing

**Objective:** As an Auth 実装者, I want OAuth callback URL から auth_code を安全に抽出できる, so that token exchange 層が一時コードを誤って扱わない

#### Acceptance Criteria

1. When `feedman://auth/callback?auth_code=<value>` is parsed, the parser shall extract `<value>` as the auth code.
2. When the callback URL has percent-encoded query values, the parser shall return the decoded `auth_code` value.
3. When the callback URL scheme is not `feedman`, the parser shall fail with a domain error.
4. When the callback URL host/path is not `auth/callback`, the parser shall fail with a domain error.
5. When `auth_code` is missing or empty, the parser shall fail with a domain error.
6. When the callback URL includes unrelated query parameters, the parser shall ignore them unless they invalidate URL parsing.
7. The parser shall not perform token exchange, Keychain persistence, ASWebAuthenticationSession control, or network calls.

### Requirement 4: Unit test coverage

**Objective:** As a QA/Developer, I want PKCE と callback parsing の unit tests がある, so that 後続の auth flow 実装前に純粋ロジックの regression を検出できる

#### Acceptance Criteria

1. When PKCE tests are run in macOS/Xcode, the test suite shall verifier の長さと文字種を検証する。
2. When PKCE tests are run in macOS/Xcode, the test suite shall RFC 7636 Appendix B の既知 verifier/challenge pair で S256 base64url 生成を検証する。
3. When PKCE tests are run in macOS/Xcode, the test suite shall invalid verifier length または invalid character を拒否することを検証する。
4. When callback parser tests are run in macOS/Xcode, the test suite shall valid `feedman://auth/callback?auth_code=...` から auth code を抽出する。
5. When callback parser tests are run in macOS/Xcode, the test suite shall wrong scheme、wrong path、missing/empty auth_code を拒否することを検証する。
6. While Linux 環境で作業している, the implementer shall Xcode build/test を実行できない制約を結果報告に明記する。

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall iOS 16+ の Swift code として利用できる。
2. The implementation shall `Feedman/Core/Auth` 配下に置き、後続の AuthRepository / ASWebAuthenticationSession 実装から再利用できる純粋ロジックにする。
3. The implementation shall View、Repository、APIClient、Keychain に依存しない。

### NFR 2: Scope control

1. The implementation shall Issue #18 の責務である PKCE generation と callback parsing に作業範囲を閉じる。
2. The implementation shall `design/SPEC-iOS.md`、`design/SERVER.md`、既存の確定済み `docs/specs/*` を勝手に変更しない。
3. The implementation shall reviewer / project-manager サブエージェント起動、PR 作成、develop への direct push を行わない。

## スコープ外

- ASWebAuthenticationSession UI の実装。
- `/auth/google/login` URL builder の完成。
- `POST /api/auth/token` の network 実装。
- access token / refresh token の保存、refresh、revoke。
- Keychain integration。
- Google OAuth 画面や SafariViewController の表示。
- Feature screen / ViewModel の実装。
- Universal Links 対応。

## 実装境界

- Core の純粋ロジックとして PKCE verifier/challenge と callback parser を提供する。
- テストは XCTest で、実ネットワーク、実 Keychain、実 OAuth、実サーバーに依存しない。
- 追加設計判断や scope 拡大が必要になった場合は実装を広げず、`impl-notes.md` の「確認事項」に列挙する。

## 確認事項

- `feedman://auth/callback` 以外の Universal Links callback URL は仕様上「or」と記載されているが、この Issue の期待する挙動は custom scheme に限定されているため、今回の実装対象から外す。
- `/auth/google/login` に渡す `code_challenge_method=S256` の要否はサーバー仕様に明記されていないため、今回の実装では challenge 生成のみを扱い、login URL builder は後続 Issue に委ねる。
