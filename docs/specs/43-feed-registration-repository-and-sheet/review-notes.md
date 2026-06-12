# Review Notes - Issue #43 - Round 1

## Summary
- `git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` は取得できた。対象は `bab1920 feat: implement feed registration sheet` の 1 commit。
- `tasks.md` と `design.md` は指定パスに存在しなかったため、`tasks.md` の `_Requirements:_` / `_Boundary:_` アノテーションとの突き合わせは実施できなかった。
- Repository、ViewModel、sheet、AppShell 連携、mock、主要 unit test は Issue #43 の要件範囲内で実装されていると判断した。

## Findings
### AC 未カバー
- [なし]

### missing test
- [なし]

### boundary 逸脱
- [なし]

## AC Coverage
- R-1.1: covered - `FeedRepository.registerFeed(url:)` が追加され、Feature は repository abstraction に依存している（根拠: Feedman/Core/FeedRepository.swift:3, Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:66）。
- R-1.2: covered - `String` の URL から `FeedRegistrationRequest(url:)` のみを作成している（根拠: Feedman/Core/FeedRepository.swift:237）。
- R-1.3: covered - real repository は `POST /api/feeds`、JSON body、Bearer access token を `APIClient` 経由で送る（根拠: Feedman/Core/FeedRepository.swift:238, Feedman/Core/APIClient.swift:106）。
- R-1.4: covered - success は `FeedRegistrationResponse` として decode して domain model へ変換している（根拠: Feedman/Core/FeedRepository.swift:238, Feedman/Core/FeedRepository.swift:164）。
- R-1.5: covered - favicon は `String?` として保持し、sheet 側で `AsyncImage` へ渡していない（根拠: Feedman/Core/APIModels.swift:173, Feedman/Core/FeedRepository.swift:149）。
- R-1.6: covered - subscription ID と feed ID を title から分離して保持し、drawer 用 `Feed` は feed ID を使う（根拠: Feedman/Core/FeedRepository.swift:143）。
- R-1.7: covered - RegisterFeed/AppShell は mockable な `FeedRepository` に依存している（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:9）。
- R-2.1: covered - submit 1 回に対する ViewModel の concurrent guard と repository の単一 API 呼び出しがある（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:81, Feedman/Core/FeedRepository.swift:237）。
- R-2.2: covered - refresh retry は sheet ではなく `APIClient` hook で処理される（根拠: Feedman/Core/APIClient.swift:128, Feedman/Core/AppEnvironment.swift:56）。
- R-2.3: covered - credentials unavailable / refresh failure は `authRequired` として ViewModel guidance に変換される（根拠: Feedman/Core/AppEnvironment.swift:95, Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:111）。
- R-2.4: covered - `FeedmanAPIError.feedmanError` context は repository で変換されず ViewModel まで届く（根拠: Feedman/Core/APIError.swift:34, FeedmanTests/FeedRegistrationRepositoryTests.swift:31）。
- R-2.5: covered - `retry_after_seconds` と `Retry-After` は context から取得される（根拠: Feedman/Core/APIError.swift:90, Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:207）。
- R-2.6: covered - transport failure / malformed response は duplicate/validation success に変換されない（根拠: Feedman/Core/APIClient.swift:191, Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:120）。
- R-2.7: covered - RegisterFeed/AppShell/DesignSystem 差分に Keychain 直接参照はない（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:66, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:9）。
- R-3.1: covered - ViewModel init は empty または initial URL の input state で開始する（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:68）。
- R-3.2: covered - whitespace-only submit は repository を呼ばず empty guidance にする（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:86, FeedmanTests/RegisterFeedViewModelTests.swift:6）。
- R-3.3: covered - submit 前に trim して request URL に使う（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:86, FeedmanTests/RegisterFeedViewModelTests.swift:19）。
- R-3.4: covered - loading state と duplicate submit guard がある（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:81, FeedmanTests/RegisterFeedViewModelTests.swift:66）。
- R-3.5: covered - loading 中は primary action が進捗を表示し、minWidth を持つ（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:59）。
- R-3.6: covered - success state は登録 feed title と identifiers を含む `RegisteredFeed` を expose する（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:98, Feedman/Core/FeedRepository.swift:143）。
- R-3.7: covered - success event を発行し、AppShell が dismiss/toast/drawer 更新に使う（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:100, Feedman/Features/AppShell/RootView.swift:264）。
- R-3.8: covered - failure 後も URL は保持され、loading 中以外は field が編集可能（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:102, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:92）。
- R-3.9: covered - sheet ごとに ViewModel を生成し、初期 state は input になる（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:15, Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:68）。
- R-4.1: covered - invalid URL / validation guidance が分岐される（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:152, FeedmanTests/RegisterFeedViewModelTests.swift:96）。
- R-4.2: covered - duplicate guidance が server outage と別に分岐される（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:136, FeedmanTests/RegisterFeedViewModelTests.swift:87）。
- R-4.3: covered - `FEED_COOLDOWN` / `rate_limit` と retry seconds 表示がある（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:144, FeedmanTests/RegisterFeedViewModelTests.swift:105）。
- R-4.4: covered - generic error は retry 可能な一般 guidance へ落ちる（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:160）。
- R-4.5: covered - transport error は network guidance に分岐される（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:120, FeedmanTests/RegisterFeedViewModelTests.swift:45）。
- R-4.6: covered - raw debug detail や token を露出せず、固定 guidance を表示している（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:111）。
- R-4.7: covered - error mapping は ViewModel/domain presentation 側にある（根拠: Feedman/Features/RegisterFeed/RegisterFeedViewModel.swift:111）。
- R-5.1: covered - drawer footer action から placeholder ではなく `RegisterFeedSheet` を表示する（根拠: Feedman/Features/AppShell/RootView.swift:59, Feedman/Features/AppShell/RootView.swift:212）。
- R-5.2: covered - SwiftUI `.sheet` と iOS 16+ compatible detents を使う（根拠: Feedman/Features/AppShell/RootView.swift:100, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:39）。
- R-5.3: covered - title、guidance、URL input、dismiss、primary action がある（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:26）。
- R-5.4: covered - URL keyboard/content type を指定している（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:92）。
- R-5.5: covered - invalid/loading 中は primary action が disabled/guarded される（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:74）。
- R-5.6: covered - success で登録 feed title と completion affordance を表示する（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:45, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:138）。
- R-5.7: covered - completion で dismiss し toast を出す（根拠: Feedman/Features/AppShell/RootView.swift:264）。
- R-5.8: covered - registered feed を drawer state に upsert する（根拠: Feedman/Features/AppShell/AppShellDrawerFeedState.swift:42, FeedmanTests/AppShellDrawerFeedStateTests.swift:75）。
- R-5.9: covered - `FeedmanTheme` と shared primitives を利用している（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:26, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:112）。
- R-5.10: covered - keyword notification / OPML / manual metadata / feed URL change controls は追加されていない（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:25）。
- R-6.1: covered - mock registration は deterministic success を返せる（根拠: Feedman/Core/FeedRepository.swift:383）。
- R-6.2: covered - mock success 後の `subscriptions()` に登録 feed を反映する（根拠: Feedman/Core/FeedRepository.swift:406）。
- R-6.3: covered - mock registration failure を注入でき、ViewModel tests も failure state を通す（根拠: Feedman/Core/FeedRepository.swift:389, FeedmanTests/RegisterFeedViewModelTests.swift:45）。
- R-6.4: covered - mock data に prototype-only `favicon_letter` / `favicon_color` はない（根拠: Feedman/Core/FeedRepository.swift:500）。
- R-6.5: covered - preview は追加されているが、AC は if added 条件であり、real network/token は使っていない（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:178）。
- R-6.6: covered - preview/test URL は `example.com` 系で secret/personal data はない（根拠: Feedman/Core/FeedRepository.swift:504, FeedmanTests/RegisterFeedViewModelTests.swift:23）。
- R-7.1: covered - dismiss、URL field、submit、loading、error、success に accessible label または shared primitive label がある（根拠: Feedman/DesignSystem/SharedPrimitives.swift:557, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:76）。
- R-7.2: covered - title/guidance/error/success text は wrap 可能な設定になっている（根拠: Feedman/DesignSystem/SharedPrimitives.swift:532, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:121）。
- R-7.3: covered - long URL は `TextField` 内に閉じ、sheet content は ScrollView に入る（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:92, Feedman/DesignSystem/SharedPrimitives.swift:507）。
- R-7.4: covered - error guidance は banner で複数行表示される（根拠: Feedman/DesignSystem/SharedPrimitives.swift:420）。
- R-7.5: covered - dismiss/control/footer button に 36〜48pt 程度の touch target がある（根拠: Feedman/DesignSystem/SharedPrimitives.swift:548, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:111）。
- R-7.6: covered - state は text/icon/ProgressView と message で区別され、色だけに依存していない（根拠: Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:59, Feedman/Features/RegisterFeed/RegisterFeedSheet.swift:127）。
- R-8.1: covered - mock `APITransport` で POST path/body/Bearer を検証している（根拠: FeedmanTests/FeedRegistrationRepositoryTests.swift:7）。
- R-8.2: covered - success fixture の値と domain mapping を検証している（根拠: FeedmanTests/FeedRegistrationRepositoryTests.swift:24）。
- R-8.3: covered - duplicate / invalid URL / rate-limit の typed error context を検証している（根拠: FeedmanTests/FeedRegistrationRepositoryTests.swift:31）。
- R-8.4: covered - empty/whitespace-only URL で repository 未呼び出しを検証している（根拠: FeedmanTests/RegisterFeedViewModelTests.swift:6）。
- R-8.5: covered - loading → success と success event を検証している（根拠: FeedmanTests/RegisterFeedViewModelTests.swift:19）。
- R-8.6: covered - loading → error と URL 維持を検証している（根拠: FeedmanTests/RegisterFeedViewModelTests.swift:45）。
- R-8.7: covered - duplicate submit が 1 repository call に抑制されることを検証している（根拠: FeedmanTests/RegisterFeedViewModelTests.swift:66）。
- R-8.8: covered - presentation state は既存 `AppShellStateTests`、success drawer update は追加 test で検証されている（根拠: FeedmanTests/AppShellStateTests.swift:102, FeedmanTests/AppShellDrawerFeedStateTests.swift:75）。
- R-8.9: covered - tests は mock transport / stub repository を使い、real network/OAuth/Keychain/token に依存していない（根拠: FeedmanTests/FeedRegistrationRepositoryTests.swift:112, FeedmanTests/RegisterFeedViewModelTests.swift:186）。
- R-8.10: covered - Developer は Xcode 未利用理由を impl-notes に記録している（根拠: docs/specs/43-feed-registration-repository-and-sheet/impl-notes.md:21）。

## Notes
- Reviewer は `xcodebuild` を追加実行していない。Developer の報告では active developer directory が CommandLineTools のため未実行（根拠: docs/specs/43-feed-registration-repository-and-sheet/impl-notes.md:27）。
- `tasks.md` が存在しないため、タスク注釈ベースの境界確認はできなかった。実差分の範囲では、Issue #43 の feed registration repository / sheet 境界を越える実装は見つからなかった。

RESULT: approve
