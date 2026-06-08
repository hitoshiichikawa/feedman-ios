# 独立レビュー notes

## Summary

- 対象: Issue #18 `PKCE generation and auth callback parsing`
- 対象 HEAD: `dfc0332090143302a584144e9a1f144b30025eca`
- Base: `develop`
- 差分取得:
  - `git diff --stat develop..HEAD`: 7 files changed, 432 insertions(+)
  - `git log --oneline develop..HEAD`: `dfc0332 feat: add pkce auth callback parsing`
- 指定された必読ファイルのうち、`docs/specs/18-pkce-generation-and-auth-callback-parsin/tasks.md` は存在しなかった。したがって `_Requirements:_` / `_Boundary:_` は参照不能で、判定は `requirements.md`、`impl-notes.md`、Issue 本文、該当差分に基づく。
- `design.md` は存在しなかった。
- Linux 環境のため `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は実行できなかった。`xcodebuild` / `swiftc` もこの環境には存在しなかった。
- `git diff --check develop..HEAD` は問題なし。

## Review Scope

判定カテゴリは依頼どおり `AC 未カバー` / `missing test` / `boundary 逸脱` のみに限定した。スタイル、命名、lint、フォーマットのみの指摘は行っていない。

## AC Coverage

- Requirement 1: PKCE verifier generation
  - `Feedman/Core/Auth/PKCE.swift` で 43...128 の長さ制約、既定 128 文字、RFC 7636 unreserved characters、`SecRandomCopyBytes` による乱数、範囲外 length の domain error を実装している。
  - `FeedmanTests/PKCETests.swift` で既定 length、許可文字、最小 length、範囲外 length を検証している。
- Requirement 2: PKCE S256 challenge generation
  - `PKCE.challenge(for:)` は verifier validation 後に `SHA256` と padding なし Base64URL 変換を行い、`plain` method support は追加していない。
  - `PKCETests` は RFC 7636 Appendix B の known pair、`=` / `+` / `/` 非含有、invalid character rejection を検証している。
- Requirement 3: Auth callback parsing
  - `Feedman/Core/Auth/AuthCallbackParser.swift` は `feedman://auth/callback?auth_code=<value>` から decoded `auth_code` を抽出し、wrong scheme、wrong host/path、missing/empty `auth_code` を domain error として扱う。
  - unrelated query parameters は無視され、token exchange、Keychain、ASWebAuthenticationSession、network call は実装していない。
- Requirement 4: Unit test coverage
  - XCTest で PKCE と callback parser の単体テストが追加されている。
  - valid callback、percent-encoded value、unrelated parameters、wrong scheme、wrong host、wrong path、missing/empty auth_code を検証している。
  - Linux で Xcode build/test を実行できない制約は `impl-notes.md` に明記されている。
- NFR / Scope
  - 追加実装は `Feedman/Core/Auth` と `FeedmanTests` を中心に閉じており、View、Repository、APIClient、Keychain への依存や scope 外の auth flow 実装は見当たらない。
  - `design/SPEC-iOS.md` / `design/SERVER.md` / 既存確定済み spec の変更は見当たらない。

## Findings

該当なし。

RESULT: approve
