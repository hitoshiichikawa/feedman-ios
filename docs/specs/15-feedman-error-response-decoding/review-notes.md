# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-10T18:47:49Z -->

## Reviewed Scope

- Branch: codex/issue-15-impl-feedman-error-response-decoding
- HEAD commit: af47cd2541db2c1d64393277552ddda062ff8db4
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `APIResponseDecoder.decode` が非 2xx で `FeedmanErrorResponse` を decode し、`FeedmanErrorContext.body` に保持。`testNonSuccessResponseWithFeedmanErrorSurfacesTypedAppError` で `code` / `message` / `category` / `action` / `details` を検証。
- 1.2 — `testFeedmanErrorWithoutDetailsDecodesAsNilDetails` で `details` なしの body が `feedmanError` として扱われ、`details == nil` になることを検証。
- 1.3 — `JSONValue` が primitive / array / object / null を表現し、`testFeedmanErrorDetailsPreserveJSONValues` で typed app error 経由の保持を検証。
- 1.4 — `FeedmanErrorResponse` / `FeedmanErrorBody` の標準 `{ error: { code, message, category, action, details? } }` 形式を `APIResponseDecoder` が直接 decode。
- 2.1 — `APIResponseDecoder.decode` が非 2xx かつ valid Feedman error body の場合に `FeedmanAPIError.feedmanError` として `statusCode` と body を surface。
- 2.2 — `FeedmanErrorContext.message` が decoded body の `message` を返し、`testNonSuccessResponseWithFeedmanErrorSurfacesTypedAppError` で検証。
- 2.3 — `FeedmanErrorContext.code` / `category` / `action` が body の文字列を返し、`testNonSuccessResponseWithFeedmanErrorSurfacesTypedAppError` で検証。
- 2.4 — `FeedmanErrorBody.category` / `action` は `String` のまま保持され、未知値 enum による decode failure を起こさない。
- 3.1 — `FeedmanErrorContext.retryAfterSeconds` が `details.retry_after_seconds` を参照し、`testFeedCooldownRetrySecondsAreInspectableFromTypedAppError` で検証。
- 3.2 — `FeedmanErrorContext.retryAfter` と `MalformedFeedmanErrorContext.retryAfter` が `Retry-After` header を保持し、valid / malformed のテストで検証。
- 3.3 — 差分は decode と metadata surface に限定され、自動 retry、待機制御、通知、UI 表示は追加されていない。
- 4.1 — `testInvalidJSONNonSuccessErrorBodySurfacesDecodeFailure` で invalid JSON が `malformedErrorResponse` と underlying `DecodingError` になることを検証。
- 4.2 — `testMalformedNonSuccessErrorBodySurfacesDecodeFailure` で必須 field 不足 body が `malformedErrorResponse` になることを検証。
- 4.3 — `testSuccessBodyDecodeFailureIsNotFeedmanErrorDecodeFailure` で 2xx success decode failure が Feedman error と混同されないことを検証。
- 4.4 — `MalformedFeedmanErrorContext` が `statusCode`、元 body、underlying error、`Retry-After` を保持。
- 5.1 — `testNonSuccessResponseWithFeedmanErrorSurfacesTypedAppError` が valid fixture の主要 field と `details` を検証。
- 5.2 — `testFeedCooldownRetrySecondsAreInspectableFromTypedAppError` が `FEED_COOLDOWN` の retry seconds を typed app error から検証。
- 5.3 — `testFeedmanErrorWithoutDetailsDecodesAsNilDetails` が optional `details` 省略を検証。
- 5.4 — invalid JSON と必須 field 不足の malformed tests が crash せず decode failure として surface されることを検証。
- 5.5 — 追加テストは fixture / inline `Data` / mock `HTTPURLResponse` のみを使い、実ネットワークへ接続しない。
- 5.6 — `impl-notes.md` に Xcode 環境制約による `xcodebuild` 失敗と、実行できた `swiftc -typecheck` の結果が記録されている。
- NFR 1.1 — `Foundation` / `Codable` / `JSONDecoder` ベースの iOS 16+ 向け実装。
- NFR 1.2 — typed app error と context が Swift 型として Repository / ViewModel から inspect 可能。
- NFR 1.3 — fixture / test data に token、Secret、個人情報は含まれていない。
- NFR 2.1 — 変更は API layer error decode と typed app error surface に限定。
- NFR 2.2 — Issue #14 の `FeedmanErrorResponse` / `FeedmanErrorBody` / `JSONValue` を利用し、既存契約を破壊していない。
- NFR 2.3 — endpoint-specific behavior は追加されていない。

## Findings

なし

## Summary

`tasks.md` と `design.md` は対象 spec directory に存在しなかったため、boundary は `requirements.md` の実装境界と `develop..HEAD` 差分で確認した。AC 未カバー、missing test、boundary 逸脱はいずれも検出しなかった。

RESULT: approve
