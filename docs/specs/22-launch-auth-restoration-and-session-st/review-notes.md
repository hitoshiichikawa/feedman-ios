# Review Notes

<!-- idd-claude:review round=1 model=claude-fable-5 timestamp=2026-06-12T08:05:37Z -->

## Reviewed Scope

- Branch: codex/issue-22-impl-launch-auth-restoration-and-session-st
- HEAD commit: 7e474f188881a5e735cda450876488adccdb46fb
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `restoreSessionAtLaunch` が `refreshTokens()` を試行 (保存 token の有無判定は #20 の repository 境界に委譲)。`testRestoreWithStoredTokenSucceedsAndShowsAuthenticatedShell` で検証。
- 1.2 — token 不在は `missingRefreshToken` 分岐で request 後の消去なし遷移。`testRestoreWithoutStoredTokenShowsLoginWithoutClearing` で検証 (repository が token 不在時に request を発行しないことは #20 の `testRefreshWithoutStoredTokenFailsWithoutRequest` で担保)。
- 1.3 — `.restoring` 中は `FeedmanLoadingView` の復元中表示。login flash なし。
- 2.1 / 2.2 — 成功時 `.authenticated(accessToken:)` へ遷移し access token をメモリ保持。同テストで検証。
- 3.1 — 拒否時 `clearLocalCredentials()` 1 回 + `.unauthenticated`。`testRestoreWithRejectedRefreshClearsCredentialsAndShowsLogin` で検証。
- 3.2 — token 不在時は消去なし。上記テストで検証。
- 3.3 — 消去は `TokenStore.clearCredentials()` へのローカル委譲のみで、server への revoke request なし。
- 4.1 — `.restoring / .unauthenticated / .authenticated` の単一 enum。
- 4.2 — 非 restoring 状態では no-op。`testRestoreIsNoOpWhenStateIsNotRestoring` で検証。
- 4.3 — `completeLogin` の遷移維持。`testCompleteLoginStillTransitionsToAuthenticated` で検証。
- 5.1〜5.3 — 5 tests すべて mock AuthRepository のみ。実ネットワーク・実 Keychain なし。
- NFR 1.1〜1.3 — ログアウト UI / 実データ読み込み / 401 hook 結線は差分に含まれない。`AuthRepository` への追加は `clearLocalCredentials` のみで既存メソッド不変 (#20/#21 の既存テスト green で担保)。

## Findings

- `RootView` の `.restoring` 分岐は単体テストで直接検証していない (SwiftUI view の状態分岐は #26 round 2 と同様 unit test の射程外)。状態決定ロジック自体は `AppEnvironment` 側でテスト済みのため blocking ではない。

## Summary

`tasks.md` と `design.md` は本 spec に存在しない (design-less 1 PR 直行ルート)。boundary は `requirements.md` の実装境界と develop..HEAD 差分で確認した。AC 未カバー、boundary 逸脱なし。

RESULT: approve
