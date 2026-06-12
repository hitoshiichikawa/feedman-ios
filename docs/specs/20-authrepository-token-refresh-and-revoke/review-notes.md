# Review Notes

<!-- idd-claude:review round=1 model=claude-fable-5 timestamp=2026-06-12T06:08:51Z -->

## Reviewed Scope

- Branch: codex/issue-20-impl-authrepository-token-refresh-and-revoke
- HEAD commit: 3ed4f7bd85b952a6a134a8366d54a0f66096f1a5
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `exchangeAuthCode` が `POST /api/auth/token` へ `{ auth_code, code_verifier }` を送信。`testExchangeSuccessSendsContractBodyAndStoresRefreshToken` で path/method/body を検証。
- 1.2 — 成功時に `saveRefreshToken(credentials.refreshToken)` 後 credentials 返却。同テストで保存値と返却値を検証。
- 1.3 — 失敗時は `FeedmanAPIError` がそのまま伝播し store 未変更。`testExchangeFailureSurfacesTypedErrorWithoutStoring` で 400 INVALID_GRANT を検証。
- 1.4 — exchange は `accessToken` を渡さず Bearer header なし。同テストで `Authorization == nil` を検証。
- 2.1 — `refreshTokens` が `loadRefreshToken()` → `POST /api/auth/refresh` へ `{ refresh_token }`。`testRefreshSendsStoredTokenAndStoresRotatedReplacement` で送信 body を検証。
- 2.2 — rotation 済み token で `saveRefreshToken` 置換。同テストで `savedTokens == ["opaque-new"]` と load 結果を検証。
- 2.3 — 保存 token 不在時は `AuthRepositoryError.missingRefreshToken` で request 不発行。`testRefreshWithoutStoredTokenFailsWithoutRequest` で検証。
- 2.4 — 401 拒否時は typed error のみで store 副作用なし。`testRefreshRejectionLeavesStoredTokenUntouched` で検証。
- 3.1 — `revokeAndClearCredentials` が Bearer 付きで `POST /api/auth/revoke` へ `{ refresh_token }`。`testRevokeSendsBearerAndClearsCredentialsOnNoContent` で header/body を検証。
- 3.2 — 204 成功時に `clearCredentials()`。同テストで clear 回数と load nil を検証。
- 3.3 — 失敗時は credential 保持。`testRevokeFailureKeepsLocalCredentials` で検証。
- 3.4 — 保存 token 不在時は request なしでローカル消去のみ。`testRevokeWithoutStoredTokenClearsLocallyWithoutRequest` で検証。
- 4.1 / 4.2 — `validateNoContent` は 2xx を成功、非 2xx を `failureError` (decode と同一変換) で error 化。revoke の 204/500 テストで両分岐を検証。
- 4.3 — `decode` は成功分岐不変・error 分岐を `failureError` へ抽出のみ。#15 の `APIResponseDecoderTests` (既存) が green であることで担保。
- 5.1〜5.4 — 8 tests すべて mock transport / mock store のみ。実ネットワーク・実 Keychain なし。
- NFR 1.1 — protocol 先行定義で mock/real 差し替え可能。NFR 1.2 — async/await。NFR 1.3 — fixture に実 token なし (ダミー文字列のみ)。
- NFR 2.1〜2.4 — ASWebAuthenticationSession / session 復元 / 401 retry hook / logout UI / access token 管理はいずれも差分に含まれない。#14/#15/#16/#19 の既存型は無変更 (追加のみ)。

## Findings

- `revokeAndClearCredentials(accessToken: nil)` の場合 Authorization header なしで送信される。仕様 (Bearer 認証下) 上、呼び出し側 (#49) は access token を保持して渡す想定であり、サーバー側は 401 を返すため安全側。要件の確認事項に記載済みのため blocking ではない。

## Summary

`tasks.md` と `design.md` は本 spec に存在しない (design-less 1 PR 直行ルート)。boundary は `requirements.md` の実装境界と develop..HEAD 差分で確認した。`APIError.swift` / `APIClient.swift` への変更は 204 対応の最小追加 + 内部抽出に閉じ、既存テスト (#15/#16) の green で後方互換を確認した。AC 未カバー、boundary 逸脱なし。

RESULT: approve
