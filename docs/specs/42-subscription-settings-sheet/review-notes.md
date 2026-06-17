# Review Notes

<!-- idd-codex:review round=3 model=gpt-5 timestamp=2026-06-16T00:28:54Z -->

## Reviewed Scope

- Issue: #42 Subscription settings sheet
- Branch: codex/issue-42-impl-subscription-settings-sheet
- HEAD commit: 12d14c0ded45f798cbd1c5c1e677c00c39ca0659
- Compared to: develop..HEAD
- 必読対象のうち `docs/specs/42-subscription-settings-sheet/tasks.md` と `docs/specs/42-subscription-settings-sheet/design.md` は存在しなかった。
- リポジトリ内に `reviewer.md` は見つからなかったため、既存 `review-notes.md` の形式を踏襲した。

## Diff / Verification

- `git diff --stat develop..HEAD`: 17 files changed, 1685 insertions(+), 68 deletions(-)。
- `git log --oneline develop..HEAD`: `12d14c0 fix: restore subscription settings boundaries` / `8bbaf95 fix: restore timeline scope for subscription settings` / `7cfeb65 feat: add subscription settings sheet`。
- `git diff --check`: 成功。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/FeedRepository.swift Feedman/Features/AppShell/AppShellState.swift Feedman/Features/AppShell/AppShellDrawerFeedState.swift Feedman/Features/Subscriptions/SubscriptionSettingsViewModel.swift`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体が必要。

## Verified Requirements

- 1.1-1.3: `Feedman/Core/FeedRepository.swift` に settings/resume/unsubscribe の repository method が追加されている。
- 1.4-1.8: real repository は `PUT /api/subscriptions/{id}/settings`、`POST /api/subscriptions/{id}/resume`、`DELETE /api/subscriptions/{id}` を Bearer auth 付きで呼び、`APIClient.sendNoContent` は 2xx no-content/body あり成功を body 必須にせず扱う。
- 1.9: `SubscriptionSettingsViewModel` と sheet は `FeedRepository` 経由で操作し、Keychain / raw `URLSession` / token refresh を直接扱っていない。
- 2.1-2.6: `Feed.subscriptionID` と `Feed.id` の分離により mutation は `Subscription.id`、feed route は `feed_id` を維持している。`subscriptionID == nil` の drawer settings button は disabled で、ViewModel 側も missing ID を fail-safe に扱う。
- 3.1-3.10: drawer settings affordance から `.sheet` + `.presentationDetents` の sheet を開き、title/current interval/status/error guidance/resume/destructive controls を表示する。keyword notification など v1 スコープ外 controls は追加されていない。
- 4.1-4.9: interval selection は保存まで endpoint を呼ばず、保存時に supported interval の body を送る。no-op、duplicate save guard、success feedback、failure recovery、auth-required mapping が実装されている。
- 5.1-5.8: stopped/error の resume は `Subscription.id` で `POST /resume` を呼び、active feed では visible action から呼ばれず、成功時は local status を active に更新する。
- 6.1-6.10: unsubscribe は destructive alert 確認後のみ `DELETE /api/subscriptions/{id}` を呼び、成功時に local removal と selected route fallback を行う。cancel は repository を呼ばない。
- 7.1-7.8: drawer row settings affordance は feed navigation と分離され、settings/resume/unsubscribe 成功後に drawer state を local update/removal する。keyword notification drawer entry は追加されていない。
- 8.1-8.8: recoverable error は日本語の sheet message に変換され、typed API error context は `FeedmanAPIError.feedmanError` と ViewModel mapping で保持・利用される。401 refresh retry は既存 `APIClient.performWithRefreshRetry` 経路を通る。
- 9.1-9.12: mock/stub repository は requested `subscriptionID` と request を記録でき、repository request tests、ViewModel state tests、AppShell local update/removal/route fallback tests が追加されている。Xcode test 未実行理由は `impl-notes.md` と実コマンド結果が一致した。

## Findings

なし。

## Summary

round=2 で指摘された #39 Feed item repository API/tests と Timeline 起動経路の boundary 逸脱は、HEAD `12d14c0` で復元されている。#42 の AC、主要 test coverage、実装境界に reject 対象となる「AC 未カバー」「missing test」「boundary 逸脱」は見つからなかった。

RESULT: approve
