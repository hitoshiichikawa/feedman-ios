# Issue #51 v1 loading error and retry polish 設計

## 概要

Issue #51 では、v1 画面に散在する loading、empty、error、retry、一時 feedback を横断的に揃える。主な対象は `Feedman/Features/*` と `Feedman/DesignSystem`、検証対象は `FeedmanTests` である。

Triage 判定理由: All v1 screens にまたがる loading / error / retry の統一は、複数の Feature モジュールと共有 UI にまたがる横断変更である。実装範囲が 3 モジュール以上に及ぶため、設計 PR ゲートを通すのが適切である。

## 目的

- v1 主要画面で初回 loading / empty / recoverable error / retry を同じ判断基準で扱う。
- refresh / pagination / mutation failure で既存 navigation state を失わない。
- typed API error を ViewModel で UI 表示可能な日本語 title/message/action へ変換する。
- #27 の shared primitive と既存 feature state を活かし、全画面リライトを避ける。
- 実装 PR が画面ごとの coverage を XCTest で確認できる粒度へ分割されるようにする。

## 非目的

- 新しい server API または API response contract の追加。
- v1 スコープ外機能の UI 表示。
- 既存 Feature ViewModel を単一の巨大な共通 state machine へ統合すること。
- グローバル toast queue / app-wide error bus の新規導入。
- 完了済み `docs/specs/*` の書き換え。

## 現状

- `Feedman/DesignSystem/SharedPrimitives.swift` に `FeedmanLoadingView`、`FeedmanCompactLoadingRow`、`FeedmanEmptyStateView`、`FeedmanRecoverableErrorView`、`FeedmanToast`、`FeedmanBannerView`、`FeedmanSheetShell` がある。
- `TimelineViewModel` / `FeedViewModel` / `StarredViewModel` は `idle` / `loading` / `loaded` / `empty` / `failed` 系 state、refresh failure、next-page failure、mutation failure message をそれぞれ持つ。
- `GlobalSearchViewModel` は idle suggestions、loading、results、empty、failed、retry、auth-required boundary を持つ。
- `ArticleDetailViewModel` は summary / loading / loaded / failed と read/star mutation feedback を扱う。
- `RegisterFeedViewModel`、`SubscriptionSettingsViewModel`、`AccountViewModel` は mutation-oriented な loading/failure/success state を持つ。
- #37 により `ItemStateCoordinator` が read/star の optimistic state と rollback を扱う。

## 設計方針

### 1. Common policy, local state machines

既存 ViewModel の state enum を残し、画面ごとに必要な文脈を保つ。Issue #51 では共通 enum への全面置換ではなく、以下の薄い descriptor / helper を必要最小限で追加する。

- initial loading / empty / error 用の表示 descriptor。
- recoverable operation ごとの retry action mapping。
- transient feedback の style / message mapping。
- API error から screen-specific presentation への small mapper。

この方針により、Timeline の pagination、Feed の cooldown、Starred の unstar restore、Search の query preservation、Account deletion の destructive confirmation など、画面固有の文脈を失わない。

### 2. Retry source of truth

retry action は「最後に失敗した操作」を曖昧に再実行しない。ViewModel は以下を別々の state として保持または既存 state で区別する。

- initial load retry: first page / current user / detail / search submit などの初回操作。
- refresh retry: pull-to-refresh または manual fetch。
- next-page retry: pagination state を使う追加読み込み。
- mutation retry: save / resume / unsubscribe / delete / star / read などの action。

即時 retry が不適切な `FEED_COOLDOWN` は retry-after message を出し、同じ tap で連打できる UI にしない。

### 3. Non-destructive failure

既に表示中の list、search query、sheet、confirmation、selected route は、recoverable failure で破壊しない。失敗時の default は次のどれかである。

- inline banner: screen 上部や sheet 内に残すべき状態説明。
- toast: 一時的で navigation を邪魔しない feedback。
- local message: form / settings / account action の context 内に表示する failure。
- full-screen recoverable error: 初回読み込み前で表示すべき content がない場合のみ。

## モジュール構成

### `Feedman/DesignSystem`

既存 `SharedPrimitives.swift` を優先利用する。実装時に不足が見つかった場合のみ、以下のような小さな型を追加してよい。

- `FeedmanFeedbackPresentation`: `title`、`message`、`style`、`actionLabel?` を持つ値型。
- `FeedmanRetryDescriptor`: `label`、`accessibilityLabel`、`isEnabled` など View に渡す retry 表示用の値型。

DesignSystem は `FeedmanAPIError` や endpoint code を直接 inspect しない。API error mapping は Feature ViewModel または Feature-local mapper の責務とする。

### `Feedman/Features/Timeline`

- 初回 loading / empty / error retry は既存 `TimelineViewState` と shared primitive を使う。
- refresh failure は existing items を維持し、banner/toast 相当の `refreshErrorMessage` を表示する。
- next-page failure は bottom retry row として `nextPageErrorMessage` を表示し、`retryNextPage()` に接続する。
- star/read mutation failure は `ItemStateCoordinator` の rollback と non-blocking feedback を保つ。

### `Feedman/Features/Feeds`

- `FeedViewState` の initial loading / empty / failed を shared primitive へ揃える。
- filter 切り替えで empty 文言が文脈に合うようにする。
- feed `stopped` / `error` は `FeedStatusBannerDescriptor` と `FeedmanBannerView` で表示し、resume action を `resumeRequestedFeedID` または既存 route に接続する。
- manual fetch の `FEED_COOLDOWN` は retry-after seconds/header を message 化し、即時 retry を促さない。
- refresh / next page / star mutation failure は visible list を保持する。

### `Feedman/Features/Starred`

- initial loading / empty / failed retry を Timeline / Feed と同じ shared primitive に揃える。
- refresh / next-page failure は既存 items を保持する。
- unstar optimistic removal failure は item を元の位置へ restore し、non-blocking feedback を表示する。
- auth-required は stale success として扱わず、既存 auth-required boundary に渡す。

### `Feedman/Features/Search`

- idle suggestions、loading、empty results、failed retry を明確に分ける。
- search failure retry は最後に submit 済みの query を使う。query text は消さない。
- result selection / detail bridge / open-link read marking failure は search screen を empty に戻さない。
- auth-required は empty results ではなく auth-required boundary として扱う。

### `Feedman/Features/ArticleDetail`

- summary-only loading、detail loading、detail failed retry を sheet 内で表示する。
- detail retry は detail load と必要な read-marking policy を既存 flow に沿って再実行する。
- read/star mutation failure は sheet を dismiss せず、field 単位 rollback と local message / toast を使う。
- original-link open failure を presenter から検知できる場合のみ feedback を出す。Presenter が失敗を返さない既存境界なら、本 Issue で広い presenter redesign はしない。

### `Feedman/Features/RegisterFeed`

- validation failure、submit loading、success、duplicate/rate-limit/network/generic failure を既存 `RegisterFeedSubmissionState` で維持する。
- failure では URL 入力を保持する。
- 429 / duplicate / invalid feed URL は action-oriented な日本語文言へ map する。
- success 後の subscription refresh feedback は #44 の境界を壊さず、登録 sheet と drawer/list refresh の navigation state を保つ。

### `Feedman/Features/Subscriptions`

- settings save / resume / unsubscribe は `operation` で busy state を表示し、duplicate tap を防ぐ。
- failure は sheet 内 message として表示し、選択値や confirmation state を不必要に消さない。
- unsubscribe は destructive confirmation を維持し、failure では成功 event を発行しない。

### `Feedman/Features/Account`

- current user loading / failed retry は shared primitive または sheet 内 error surface に揃える。
- logout / deletion in-flight は duplicate tap を防ぎ、成功時のみ session transition を行う。
- deletion failure は authenticated session と account sheet context を維持する。
- auth-required は既存 AppEnvironment / RootView の session-loss policy に合わせる。

### `Feedman/Features/AppShell`

- Drawer subscriptions の loading / empty / failed / retry を扱いつつ、Timeline、Starred、Search、Account などの global route は利用可能に保つ。
- subscriptions reload が失敗した場合、可能なら前回 feed rows を保持し、最新 reload が失敗したことを non-destructive に示す。
- route / feed / filter が変わった後の stale async response が現在の route state を上書きしないことを確認する。

### `Feedman/Features/Login` and `Feedman/Core/AppEnvironment`

- login in-flight 中の duplicate tap を抑止し、cancel / failure 後に login retry 可能な状態へ戻す。
- launch auth restoration failure は既存 AuthRepository / TokenStore 境界で credentials を clear し、unauthenticated state に遷移する。
- token / Authorization header / refresh token は UI feedback、log、test output に出さない。

## Error mapping baseline

Feature-local mapper は既存文言を優先するが、retry 可否と action は以下の基準に揃える。

| Error / condition | 表示方針 | Retry / action |
| --- | --- | --- |
| `FeedmanAPIError.transportFailed` | 通信状況の確認を促す日本語文言 | recoverable operation なら retry |
| `FeedmanAPIError.authRequired` | 認証期限切れまたは再ログインが必要な状態 | 既存 auth-required / session-loss boundary |
| `FEED_COOLDOWN` / 429 retry-after | 待機時間を含む案内 | 即時 retry を促さない |
| duplicate feed | 登録済みであることを案内 | URL 修正または dismiss |
| validation / invalid URL | 入力内容の修正を促す | 入力保持、submit 可能 |
| malformed / unknown response | 汎用 recoverable error | context に応じて retry |
| destructive mutation failure | 成功扱いせず、session / confirmation context を保持 | explicit retry or cancel |

## データモデル / 公開 IF

Issue #51 では public API model の変更は想定しない。追加する場合は UI presentation 用の値型に限定する。

候補:

```swift
struct FeedmanFeedbackPresentation: Equatable {
    let title: String?
    let message: String
    let style: FeedmanToast.Style
    let actionLabel: String?
}
```

```swift
struct FeedmanRecoverableActionPresentation: Equatable {
    let title: String
    let message: String
    let retryLabel: String
    let isRetryEnabled: Bool
}
```

これらは DesignSystem に置く場合も Feature-local に置く場合も、API layer に依存しない。`FeedmanAPIError` からの mapping は各 Feature ViewModel の static helper または private extension に置く。

## 処理フロー

### Initial load

1. View appears / sheet opens / search is submitted。
2. ViewModel が duplicate in-flight を guard し、loading state に入る。
3. Repository が成功した場合、items/data が空なら empty、非空なら loaded へ遷移する。
4. Repository が recoverable error を返した場合、content がなければ full-screen/sheet recoverable error を表示する。
5. Retry tap は同じ initial operation を再実行する。

### Refresh / pagination

1. User が pull-to-refresh、manual fetch、または sentinel を起動する。
2. 既存 items は保持し、operation-specific loading indicator を表示する。
3. 成功時は該当 snapshot / pagination state を更新し、operation-specific error を clear する。
4. 失敗時は既存 items を保持し、refresh feedback または next-page retry を表示する。
5. Auth-required は stale loaded state として扱わず route owner に通知する。

### Stale async response

1. ViewModel は feed id、filter、query、route、item id などの request session key を必要に応じて保持する。
2. Response completion 時、session key が現在の visible context と一致する場合だけ state を更新する。
3. 一致しない response は破棄し、現在の loading / loaded / error state を上書きしない。
4. Cancellation を success や destructive mutation success として扱わない。

### Mutation

1. User action が ViewModel に入る。
2. ViewModel は duplicate in-flight を guard し、必要なら optimistic state を適用する。
3. 成功時は confirmed state / success event / session transition を適用する。
4. 失敗時は必要な rollback を行い、sheet / route / input を保持したまま failure feedback を出す。
5. Destructive operation は retry 前にも explicit action または confirmation boundary を保つ。

## リスク

- 画面ごとに既に state enum があるため、過度に共通化すると context-specific retry を壊す。実装は descriptor と mapping に留める。
- Auth-required を通常 error と同じ retry にすると無限 retry になり得る。各 ViewModel test で auth-required boundary を固定する。
- Toast / banner をグローバルに統合すると scope が膨らむ。既存 feature-local feedback を許容しつつ、重複表示や navigation state loss の修正を優先する。
- Starred unstar restore、Account deletion、Subscription unsubscribe は破壊的または item removal を伴うため、success event と failure event の誤発行を重点的に検証する。
- 全 v1 画面を一度に実装すると差分が大きい。実装時に大きくなる場合は、画面群ごとの追加子 Issue に分割する。

## テスト方針

`FeedmanTests` の既存 ViewModel tests を中心に不足 coverage を追加する。実ネットワーク、実 Keychain、実 OAuth は使わない。

重点観点:

- slow repository operation 中に loading / busy state が見える。
- empty response が error ではなく empty state になる。
- initial error retry が first load を再実行する。
- refresh failure が visible items / query / sheet を保持する。
- next-page failure が existing items と `canLoadMore` を保持し、retry 成功で clear される。
- mutation failure が rollback / feedback / navigation preservation を満たす。
- `FEED_COOLDOWN` が retry-after guidance を表示する。
- `FeedmanAPIError.authRequired` が auth-required boundary を通る。
- stale async response が現在の feed/filter/query/route state を上書きしない。
- login cancel / auth restoration failure が login retry または unauthenticated state に戻る。

## 検証

macOS/Xcode 環境では以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Xcode が利用できない環境では、実行不可理由を実装 PR の結果報告に明記し、最低限以下を実行する。

```bash
plutil -lint Feedman.xcodeproj/project.pbxproj
git diff --check
```

## 確認事項

- 既存 `FeedmanToast` の replacement / queue policy を変更するかは実装時に差分量で判断する。Issue #51 の必須条件は「重複して操作不能にしない」ことであり、app-wide toast center 新設ではない。
- original-link open failure は現時点の presenter が failure を返せる場合にだけ扱う。返せない場合は follow-up として明記する。
- Logout の最終 failure policy は既存 #49 の実装内容に合わせる。Issue #51 で logout flow を再設計しない。
