# Issue #51 v1 loading error and retry polish 実装メモ

## Implementation Notes

### Task 1

Baseline audit として、実装変更は行わず、既存の DesignSystem primitive、v1 主要画面の ViewModel/View、関連 XCTest の loading / empty / error / retry / transient feedback / stale async response 対策を確認した。

採用方針:

- 既存の `FeedmanLoadingView`、`FeedmanCompactLoadingRow`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanToast`、`FeedmanBannerView`、`FeedmanSheetShell` を継続利用する。DesignSystem は API error code を inspect しておらず、error mapping は Feature/ViewModel 側に閉じている。
- Timeline / Feed / Starred / Search / ArticleDetail は、画面ごとの state enum と operation-specific retry を維持する。共通 state machine へ置換する必要はない。
- Mutation failure は既存 `ItemStateCoordinator` と feature-local message/banner で扱い、sheet / route / visible list を保持する方針を継続する。
- Stale async response 対策は、Feed の `Session` / pending first-page、Search の `currentRequestID` と task cancellation、Drawer subscriptions の `loadGeneration` を中心に既存実装を活かす。

確認できた主な coverage:

- Timeline は initial loading / empty / error retry、refresh failure preservation、next-page retry、star rollback が実装・テスト済み。
- Feed list は filter empty、status banner、manual refresh cooldown (`retry_after_seconds` / `Retry-After` fallback)、manual refresh failure preservation、pagination retry、feed/filter 変更中の stale next-page response 抑制が実装・テスト済み。
- Starred は initial / refresh / pagination、unstar failure restore、auth-required boundary が実装・テスト済み。
- Search は suggestions / loading / empty / failed retry、auth-required boundary、query preservation、古い検索 response の破棄が実装・テスト済み。
- Article detail は summary + loading、detail failure retry、read/star mutation rollback、invalid original-link feedback が実装・テスト済み。
- RegisterFeed は submit loading、input preservation、duplicate / invalid URL / rate-limit / network / auth-required mapping、success event の一回配送が実装・テスト済み。
- AppShell drawer は subscriptions loading / empty / failed retry、既存 feed preservation、登録後 refresh failure preservation、latest reload wins が実装・テスト済み。
- Login / auth restoration は duplicate login prevention、cancel/failure retryable state、restore failure で credential clear + unauthenticated transition が実装・テスト済み。

残存課題 / 後続 task 候補:

- Timeline / Feed の list 系 ViewModel は `FeedmanAPIError.authRequired` を初回/refresh/pagination で明示的な auth boundary に渡していない。後続 auth-required handling task で確認・補強する。
- Starred / Search / ArticleDetail の auth-required failed state は callback を呼ぶ一方で retry button も表示する。再ログイン誘導との二重導線が意図通りか後続 task で整理する。
- SubscriptionSettings は save failure の selection preservation はテスト済みだが、resume / unsubscribe failure で confirmation context と sheet state を保持する観点のテストが薄い。
- Account logout は現状 placeholder で、実 logout の in-flight / failure / local clear policy は未接続。logout 実装接続後に Issue #51 の polish 対象として再確認が必要。
- Drawer 内の global route は Timeline / Starred / Account / feed registration があり、Search は toolbar 経由で利用できるが drawer entry としては存在しない。design.md の「Drawer subscriptions 中も Search など global entries が利用可能」との読み合わせが必要。
- ArticleDetail の original-link open は URL validation と Safari presentation までで、`SFSafariViewController` 側の表示失敗は現行 presenter 境界では検知できない。広い presenter redesign は task 1 scope 外。
- Timeline には route/feed/query 相当の request session key がなく、初回/refresh overlap は duplicate guard に依存している。実害は限定的だが、route 変更後 stale response の横断 test coverage としては Feed/Search/Drawer より薄い。

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

### Task 2

採用方針: DesignSystem に API error 非依存の `FeedmanRetryDescriptor` を追加し、既存 `FeedmanRecoverableErrorView` の retry 表示補助として後方互換で接続した。

重要な判断:

- `FeedmanFeedbackPresentation` 相当の toast/banner 共通値型は追加しない。既存の `FeedmanToastCenter` は current toast を置換する deterministic policy を持ち、banner/local message も feature-local state で単一表示に収まっているため。
- `FeedmanRetryDescriptor` は label / accessibilityLabel / isEnabled だけに絞り、`FeedmanAPIError` や endpoint code の inspect は引き続き Feature/ViewModel 側に閉じた。
- Timeline / Feed / Starred / Search / ArticleDetail / Account の初回 recoverable retry は、ボタン表示名を変えずに画面固有の VoiceOver label を渡す形へ揃えた。

残存課題: なし。auth-required の二重導線整理や画面別 mutation polish は後続 task の scope で扱う。

Finding Closure Matrix:

| Finding | Target | Category | 変更ファイルまたは commit | 実行したテスト | status |
| --- | --- | --- | --- | --- | --- |
| 前回 reject finding なし | Task 2 | N/A | N/A | `plutil -lint Feedman.xcodeproj/project.pbxproj`; `git diff --check`; `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は CommandLineTools のため実行不可 | closed |

検証:

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 実行不可。`xcode-select` の active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。
