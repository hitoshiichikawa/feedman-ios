# Issue #51 v1 loading error and retry polish タスク分割

## 1. Baseline audit

- [x] `Feedman/DesignSystem/SharedPrimitives.swift` の loading / empty / recoverable error / toast / banner / sheet shell API を確認する。
- [x] `TimelineViewModel` / `TimelineView` の initial / refresh / pagination / mutation failure 表示を確認する。
- [x] `FeedViewModel` / `FeedView` の initial / filter empty / status banner / manual refresh cooldown / pagination / mutation failure 表示を確認する。
- [x] `StarredViewModel` / `StarredView` の initial / refresh / pagination / unstar failure / auth-required 表示を確認する。
- [x] `GlobalSearchViewModel` / `GlobalSearchView` の idle / loading / empty / error / retry / auth-required / query preservation を確認する。
- [x] `ArticleDetailViewModel` / `ArticleDetailSheet` の loading / error retry / read-star failure / open-link boundary を確認する。
- [x] `RegisterFeedViewModel` / `RegisterFeedSheet`、`SubscriptionSettingsViewModel` / sheet、`AccountViewModel` / view の mutation busy/failure 表示を確認する。
- [x] `AppShell` drawer subscriptions と `Login` / `AppEnvironment` auth restoration の loading / failure / retry を確認する。
- [x] route / feed / filter / query / selected item 変更後の stale async response 対策を確認する。
- [x] 不足が小さい修正で収まるか、追加子 Issue が必要かを実装 PR の冒頭で判断する。

## 2. Shared presentation helpers

- [x] 2. Shared presentation helpers

- [ ] 必要な場合のみ、DesignSystem または Feature-local に `FeedmanFeedbackPresentation` 相当の小さな値型を追加する。
- [ ] 必要な場合のみ、recoverable retry 表示用 descriptor を追加する。
- [ ] DesignSystem helper が `FeedmanAPIError` や endpoint code を直接参照しないことを確認する。
- [ ] loading / error / retry control の accessibility label と disabled state を確認する。
- [ ] Toast / banner が同時に複数重なって操作不能にならない policy を既存実装に合わせて固定する。
- [ ] Toast / banner / local message が Dynamic Type と VoiceOver で読め、dismiss や navigation control を塞がないことを確認する。

## 3. Timeline polish

- [x] 3. Timeline polish

- [ ] 初回 loading / empty / recoverable error が shared primitive に揃っていることを確認し、不足を修正する。
- [ ] `retryInitialLoad()` が first-page load のみを再実行することをテストで固定する。
- [ ] refresh failure が既存 items を保持し、non-destructive feedback を表示することを確認する。
- [ ] `retryNextPage()` が next-page request のみを再実行することをテストで固定する。
- [ ] read/star mutation failure が navigation state と selected item を失わないことを確認する。

## 4. Feed list polish

- [x] 4. Feed list polish

- [ ] filter 別 empty state の文言と表示条件を確認する。
- [ ] feed stopped/error banner と resume 導線が shared banner 表現に沿うことを確認する。
- [ ] manual refresh `FEED_COOLDOWN` の retry-after message を `details.retry_after_seconds` / `Retry-After` から表示することを確認する。
- [ ] manual refresh generic failure が items を保持し、actionable feedback を出すことをテストで固定する。
- [ ] next-page failure retry と star mutation failure feedback を確認する。

## 5. Starred polish

- [ ] 初回 loading / empty / failed retry の表示を Timeline / Feed と揃える。
- [ ] refresh failure が既存 starred items を保持することをテストで固定する。
- [ ] next-page failure retry が pagination reset を起こさないことを確認する。
- [ ] unstar failure が削除済み item を元の位置へ restore し、feedback を出すことをテストで固定する。
- [ ] auth-required が stale success や empty として表示されないことをテストで固定する。

## 6. Search and detail polish

- [ ] Search idle suggestions / loading / empty / failed retry の表示条件を確認する。
- [ ] Search retry が最後に submit 済みの query を使い、query text を保持することをテストで固定する。
- [ ] Search result selection から detail error が起きても search state を empty に戻さないことを確認する。
- [ ] Article detail の summary loading / detail loading / failed retry を sheet 内で一貫表示する。
- [ ] Article detail read/star mutation failure が sheet を dismiss せず feedback を出すことをテストで固定する。
- [ ] original-link open failure が現行 presenter で検知できない場合は、実装メモに follow-up として残す。

## 7. Forms, settings, account polish

- [ ] Feed registration failure で URL 入力が保持されることをテストで固定する。
- [ ] Feed registration duplicate / invalid URL / rate-limit / network / generic error の表示文言を確認する。
- [ ] Subscription settings の save / resume / unsubscribe failure が sheet context と選択値を保持することをテストで固定する。
- [ ] Account current-user loading / failure retry を確認する。
- [ ] Logout / account deletion の in-flight / failure / success session transition が既存 #49 / #50 policy に沿うことを確認する。
- [ ] Destructive operation retry が confirmation または explicit action boundary を維持することを確認する。

## 8. Cross-screen auth-required handling

- [ ] Timeline / Feed / Starred / Search / ArticleDetail / RegisterFeed / SubscriptionSettings / Account で `FeedmanAPIError.authRequired` の扱いを確認する。
- [ ] Auth-required を empty state や generic success として扱っている箇所があれば修正する。
- [ ] Route owner へ auth-required callback がある画面は callback が呼ばれることをテストで固定する。
- [ ] Callback がない画面は既存 session-loss policy と矛盾しない visible error を表示する。

## 9. AppShell, login, and stale response

- [ ] Drawer subscriptions loading / empty / failed / retry 中も global route entries が利用可能であることを確認する。
- [ ] subscriptions reload failure 後に前回 feed rows を保持できる場合は保持し、最新 reload failure を表示する。
- [ ] Login cancel / failure 後に login retry 可能な状態へ戻ることを確認する。
- [ ] Launch auth restoration failure が credentials clear と unauthenticated transition を通ることを確認する。
- [ ] Feed id / filter / search query / selected item が変わった後、古い response が現在 state を上書きしないことをテストで固定する。
- [ ] Token / Authorization header / private search or article content が log/test output に出ないことを確認する。

## 10. Suggested implementation slices

- [ ] Slice 1: baseline audit + shared presentation helper の最小補強。
- [ ] Slice 2: list 系 Timeline / Feed / Starred の loading / retry / refresh / pagination polish。
- [ ] Slice 3: Search / ArticleDetail の retry / stale response / sheet feedback polish。
- [ ] Slice 4: RegisterFeed / SubscriptionSettings / Account の mutation feedback polish。
- [ ] Slice 5: AppShell drawer / Login / auth-required / final verification。
- [ ] 1 PR で大きすぎる場合は、上記 slice を追加子 Issue として提案する。

## 11. Tests

- [ ] Slow repository operation 中の loading / busy state を各主要 ViewModel test に追加または確認する。
- [ ] Empty response と recoverable error retry の test coverage を確認する。
- [ ] Refresh failure preservation の test coverage を Timeline / Feed / Starred / Search で確認する。
- [ ] Next-page failure retry の test coverage を Timeline / Feed / Starred で確認する。
- [ ] Mutation failure navigation preservation の test coverage を read/star / registration / settings / account で確認する。
- [ ] Cooldown / retry-after message の test coverage を確認する。
- [ ] Auth-required boundary の test coverage を確認する。
- [ ] Stale response suppression の test coverage を確認する。

## 12. Final verification

- [ ] `plutil -lint Feedman.xcodeproj/project.pbxproj` を実行する。
- [ ] `git diff --check` を実行する。
- [ ] macOS/Xcode 環境で以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- [ ] Xcode が利用できない場合は、実行不可理由を実装 PR の結果報告に明記する。
- [ ] 実装が大きくなった場合は、画面群ごとの追加子 Issue 分割案を Issue #51 または PR の確認事項に記載する。
