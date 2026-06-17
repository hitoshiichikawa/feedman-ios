# Issue #50 reviewer notes round=1/2

## Summary

- 必読ファイルとして `AGENTS.md`、`requirements.md`、`impl-notes.md` を確認した。
- `docs/specs/50-account-deletion-confirmation-flow/tasks.md` は存在しなかった。
- `docs/specs/50-account-deletion-confirmation-flow/design.md` は存在しなかった。
- 差分取得として `git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` を実行し、差分は空ではなかった。対象 commit は `be7fe15 feat: add account deletion confirmation flow` と `c22122d docs: add account deletion requirements`。
- `_Boundary:_` は `tasks.md` 欠落のため確認できないが、requirements の実装境界に照らすと、変更は Account feature、Core の repository / APIClient / AppEnvironment、FeedmanTests、当該 spec 追加に収まっている。
- 検証として `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 17' test` を実行し、236 tests / 0 failures で成功した。

## Findings

なし。

## Coverage Notes

- AC 1.x: `AccountView` の destructive alert は、退会文言、取り消し不可の説明、cancel / destructive confirm を提供している。根拠: `Feedman/Features/Account/AccountView.swift:61`, `Feedman/Features/Account/AccountView.swift:65`, `Feedman/Features/Account/AccountView.swift:68`, `Feedman/Features/Account/AccountView.swift:75`。未ロード・認証なしの実行抑止は `AccountViewModel` 側で failed state に落としている。根拠: `Feedman/Features/Account/AccountViewModel.swift:134`。
- AC 2.x: 確認後の `DELETE /api/users/me` は repository 境界経由で、APIClient の Bearer token / refresh retry に委譲されている。根拠: `Feedman/Core/AccountRepository.swift:4`, `Feedman/Core/AccountRepository.swift:18`, `Feedman/Core/APIClient.swift:91`, `Feedman/Core/APIClient.swift:145`。重複 request 防止と progress 表示も確認した。根拠: `Feedman/Features/Account/AccountViewModel.swift:160`, `Feedman/Features/Account/AccountViewModel.swift:175`, `Feedman/Features/Account/AccountView.swift:196`。
- AC 3.x / 4.x: 成功時は `AppEnvironment.clearLocalAuthenticationAfterAccountDeletion()` で local credentials と in-memory token を消去し、unauthenticated へ遷移する。失敗時と cancellation は session clear completion を呼ばず failed / idle に留める。根拠: `Feedman/Core/AppEnvironment.swift:96`, `Feedman/Features/Account/AccountViewModel.swift:177`, `Feedman/Features/Account/AccountViewModel.swift:181`, `Feedman/Features/Account/AccountViewModel.swift:183`。
- AC 5.x: AccountRepository protocol、real implementation、ViewModel の deletion state、`@MainActor` 境界、AppEnvironment への session clear 委譲を確認した。根拠: `Feedman/Core/AccountRepository.swift:3`, `Feedman/Core/AccountRepository.swift:18`, `Feedman/Features/Account/AccountViewModel.swift:43`, `Feedman/Features/Account/AccountViewModel.swift:76`, `Feedman/Features/AppShell/RootView.swift:219`。
- AC 6.x: ViewModel tests は confirmation、cancel、success、failure、duplicate request prevention を mock repository / mock session completion で検証している。repository tests は method / path / Bearer / no body と 2xx body success を検証している。AppEnvironment tests は credential clear、unauthenticated transition、revoke 非呼び出しを検証している。根拠: `FeedmanTests/AccountViewModelTests.swift:125`, `FeedmanTests/AccountViewModelTests.swift:136`, `FeedmanTests/AccountViewModelTests.swift:156`, `FeedmanTests/AccountViewModelTests.swift:178`, `FeedmanTests/AccountViewModelTests.swift:208`, `FeedmanTests/AccountRepositoryTests.swift:58`, `FeedmanTests/AccountRepositoryTests.swift:74`, `FeedmanTests/AppEnvironmentSessionRestoreTests.swift:96`。

RESULT: approve
