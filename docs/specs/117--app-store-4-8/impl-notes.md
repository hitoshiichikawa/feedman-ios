## Implementation Notes

### Task 1

- 採用方針: Passkey API の request / response DTO と `PasskeyRepository` protocol / real implementation を Core 境界に追加し、View / ViewModel から network や credential raw data を直接扱わない前提を作った。
- 重要な判断: `options.publicKey` wrapper は必須 decode とし、欠落時は decode failure に倒す。`registration/finish` は `{user_id}` のみを decode し、`authentication/begin` request は `{code_challenge}` のみを送るテストで未知 field 混入を防いだ。
- 重要な判断: サーバ側 #216 は 2026-07-24 時点で GitHub Issue は open だが `staged-for-release` label 付きで、repo 運用上は develop merge 済みを示すため task 1 の依存は満たすものとして実装した。
- 残存課題: 次 task では coordinator 側で base64url string を AuthenticationServices の `Data` に変換する。Task 1 では repository DTO 上の base64url 文字列保持までを対象にした。

## AC Coverage Matrix

| Requirement / AC | Implementation path | Production entrypoint / owning flow | Test / assertion | Verification result | Notes |
|------------------|---------------------|-------------------------------------|------------------|---------------------|-------|
| 2.3 | `Feedman/Core/APIModels.swift` `PasskeyRegistrationBeginRequest`; `Feedman/Core/PasskeyRepository.swift` `beginRegistration` | Login signup flow repository boundary | `PasskeyRepositoryTests.testBeginRegistrationPostsUsernameAndCodeChallengeOnly` | `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` passed (507 tests) | recovery email / credential_id を送らないことも確認 |
| 2.5 | `PasskeyRegistrationFinishRequest`, `PasskeyRegistrationFinishResponse`, `finishRegistration` | Login signup flow repository boundary | `PasskeyRepositoryTests.testFinishRegistrationPostsChallengeAndCredentialAndDecodesUserIDOnly` | same xcodebuild passed | `{user_id}` のみを token handoff として扱わない DTO 境界 |
| 3.2 | `PasskeyAuthenticationBeginRequest`; `beginAuthentication` | Login passkey flow repository boundary | `PasskeyRepositoryTests.testBeginAuthenticationPostsCodeChallengeOnly` | same xcodebuild passed | `credential_id` / `allow_credentials` を server request に送らないことを確認 |
| 3.4 | `PasskeyAuthenticationFinishRequest`, `PasskeyAuthenticationFinishResponse`, `finishAuthentication` | Login passkey flow repository boundary | `PasskeyRepositoryTests.testFinishAuthenticationPostsCredentialAndDecodesAuthCode` | same xcodebuild passed | token exchange は後続 task scope |
| 4.2 | `beginAddRegistration(accessToken:)` | Account passkey add repository boundary | `PasskeyRepositoryTests.testBeginAddRegistrationUsesBearerTokenAndEmptyJSONBody` | same xcodebuild passed | Bearer token と空 JSON body を確認 |
| 4.4 | `finishAddRegistration(challengeID:credential:accessToken:)` | Account passkey add repository boundary | `PasskeyRepositoryTests.testFinishAddRegistrationUsesBearerTokenAndAcceptsNoContent` | same xcodebuild passed | 204 no-content を成功扱い |
| 4.7 | `APIClient` refresh retry hook delegation via `FeedmanPasskeyRepository` add endpoint calls | Account passkey add repository boundary | `PasskeyRepositoryTests.testAddRegistrationDelegatesExpiredTokenRefreshToAPIClient` | same xcodebuild passed | Account feature 独自 refresh は未実装 |
| 6.6 | `UserResponse.username` optional decode | Account repository current user boundary | `PasskeyRepositoryTests.testUserResponseDecodesOptionalUsername`; existing `AccountRepositoryTests.testUserResponseDecodesMobileCurrentUserContractFields` | same xcodebuild passed | 表示 precedence は Account task scope |
| 8.2 | `PasskeyRepository` protocol and `FeedmanPasskeyRepository` isolate APIClient access | Repository boundary | `PasskeyRepositoryTests` request tests | same xcodebuild passed | View code は未変更 |
| 8.3 | DTOs keep raw credential fields only in request envelope and do not log secrets | Repository / Codable boundary | `PasskeyRepositoryTests.testCredentialEnvelopePreservesBase64URLFields`; diff review | same xcodebuild passed; `git diff --check` passed | ログ処理は追加なし |
| 8.5 | XCTest with mock `APITransport`, no real network / Keychain / biometric dependency | Test boundary | `PasskeyRepositoryTests` uses `PasskeyRecordingTransport` | same xcodebuild passed | 実 Face ID / Touch ID は未使用 |
| 8.6 | Repository regression coverage for passkey success / failure, add success / failure, refresh retry | XCTest suite | `PasskeyRepositoryTests` 11 cases | same xcodebuild passed | Login/UI duplicate guard は後続 task scope |

## Verification

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/PasskeyRepositoryTests test` passed (11 tests).
- `plutil -lint Feedman.xcodeproj/project.pbxproj Feedman/Info.plist` passed.
- `git diff --check` passed.
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` passed (507 tests).

STATUS: complete
