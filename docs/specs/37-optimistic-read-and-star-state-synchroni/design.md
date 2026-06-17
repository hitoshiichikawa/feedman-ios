# Issue #37 Optimistic read and star state synchronization 設計

## 概要

Issue #37 では、一覧、検索結果、記事詳細 sheet に表示される同一 item の `isRead` / `isStarred` を app session 内で同期し、Repository mutation 失敗時に field 単位で rollback する。

本 Issue は Core/State、Timeline、Feed、ArticleDetail、Search の visible state を横断するため design PR gate 対象とする。Triage 判定理由は、read/star の楽観更新とロールバックが Core/State, Timeline, ArticleDetail を横断し、軽微な修正ではなく共有状態の設計方針を先に固める必要があるためである。

Depends on: #32, #34, #35

## 目的

- card / detail の star toggle を即時に visible screens へ反映する。
- detail open 時の read marking を一覧側にも即時反映する。
- mutation failure 時は失敗した field だけを前の visible value へ戻す。
- `ItemRepository.updateItemState` の partial update 契約を維持する。
- API model を mutable global model にせず、表示時に effective state を合成する。

## 非目的

- Feed unread count の楽観更新。
- app relaunch 後の state 復元や永続化。
- SFSafariViewController presenter の新規実装。
- 新規サーバー API、server response body の要求、`design/SPEC-iOS.md` / `design/SERVER.md` の変更。
- keyword notification UI、feed-scoped search UI、スター一覧の新規実装。

## 現状

- `ItemStateChange(itemID,isRead,isStarred)` は `Feedman/Core/Models.swift` に存在する。
- `ItemRepository.updateItemState(id:request:accessToken:)` は `PUT /api/items/{id}/state` の partial update を提供する。
- `TimelineViewModel` / `FeedViewModel` は `items: [ItemSummary]` と `localStarOverrides` を持ち、現在は local star toggle のみで server mutation と rollback を持たない。
- `ArticleDetailViewModel` は `onItemStateChange` callback を持つが、read/star mutation 成功後の通知に近い。
- `RootView` は `shellState.applyItemStateChange(change)` を行うが、Timeline / Feed へ state change を配っていない。
- `GlobalSearchViewModel` は `itemStateChange` を受けて visible hit に `applyItemStateChange` できる。

## 設計方針

`Feedman/Core/State` 配下に app-session scoped な `ItemStateCoordinator` を追加する。`RootView` が `@StateObject` として保持し、Timeline、Feed、ArticleDetail、Search、および open-link read marking の境界へ注入する。global singleton にはしない。

`ItemStateCoordinator` は item id ごとに read / star の effective state と pending mutation を持つ。`ItemSummary`、`ItemDetail`、`ItemSearchHit` の API model 自体は変更可能な source of truth にせず、ViewModel または descriptor 作成時に coordinator の effective state を合成する。

## Core/State の責務

追加候補:

- `ItemStateCoordinator`: `@MainActor ObservableObject`。app session 中の visible effective state、pending mutation、rollback metadata を管理する。
- `ItemStateField`: `.read` / `.starred`。
- `ItemStateSnapshot`: `isRead`、`isStarred`、`isReadPending`、`isStarredPending` を表示層へ渡す小さな値。
- `ItemStateMutationToken`: field 単位 rollback のための `UUID` metadata。

Coordinator は以下を提供する。

- `effectiveState(itemID:baseRead:baseStarred:)`
- `applyEffectiveState(to: ItemSummary)` / `ItemDetail` / `ItemSearchHit` 相当の mapping
- `isPending(itemID:field:)`
- read marking mutation の begin / commit / rollback
- star mutation の begin / commit / rollback
- `ItemStateChange` 互換通知または published change による既存 Search bridge

## Effective state 合成

When an item is rendered, the UI shall derive read/star from repository model plus coordinator overlay.

優先順位:

1. 同一 item / field に pending optimistic value があればそれを使う。
2. pending がなく、session 内で成功済み local value があればそれを使う。
3. どちらもなければ repository から受け取った `ItemSummary` / `ItemDetail` / `ItemSearchHit` の値を使う。

成功済み local value は current app session 内の表示一貫性を守るため保持する。後続 refresh が同じ値を返した field は overlay を prune してよい。pending 中の refresh は optimistic value を消してはならない。

## Mutation flow

### Star toggle

When the user toggles star from Timeline, Feed, or ArticleDetail, the app shall:

1. 現在の effective star value を読み、target を反転する。
2. 同一 item / `.starred` が pending なら control を disabled とし、新規 mutation を開始しない。
3. coordinator に field 単位の previous value と token を記録し、target を optimistic value として publish する。
4. `ItemRepository.updateItemState` を `ItemStateUpdateRequest(isRead: nil, isStarred: target)` で呼ぶ。
5. 成功時は target を confirmed local value として残し、pending を解除する。
6. 失敗時は token が current pending と一致する場合だけ `.starred` を previous value へ rollback し、pending を解除する。
7. 失敗時は「スターを更新できませんでした。」相当の non-blocking toast / message を出す。

### Read marking

When ArticleDetail opens an unread effective item, the app shall:

1. current effective read value を確認する。
2. 既に read なら mutation を skip してよい。
3. unread なら coordinator に `.read` の previous value と token を記録し、`true` を optimistic value として publish する。
4. `ItemRepository.updateItemState` を `ItemStateUpdateRequest(isRead: true, isStarred: nil)` で呼ぶ。
5. 成功時は `true` を confirmed local value として残し、pending を解除する。
6. 失敗時は `.read` だけを previous value へ rollback し、「既読状態を更新できませんでした。」相当の non-blocking error を出す。
7. detail sheet は read marking failure で自動 dismiss しない。

既存 open-original / external-link action が read marking を行う場合も同じ coordinator flow を使う。ただし Safari presentation の新規実装は本 Issue に含めない。

## Concurrent policy

同一 item / field の pending mutation 中は control を disabled にする。これを第一候補とし、latest-intent queue や mutation coalescing は導入しない。

read と star は別 field として独立に扱う。If read mutation fails, it shall not roll back star. If star mutation fails, it shall not roll back read. 同一 item で read pending と star pending が同時に存在しても、それぞれの field と token で rollback を判定する。

## View integration

### RootView

`RootView` が `ItemStateCoordinator` を app session scoped に保持し、以下へ渡す。

- `TimelineView` / `TimelineViewModel`
- `FeedView` / `FeedViewModel`
- `ArticleDetailSheet` / `ArticleDetailViewModel`
- `GlobalSearchView` または既存 `itemStateChange` bridge
- `AppShellSearchResultOpenLinkCoordinator`

mutation failure の user feedback は既存 `FeedmanToastCenter` を優先する。Feature-local message が既にある `ArticleDetailViewModel` は sheet 内 message と toast の重複を避ける。

### Timeline / Feed

`localStarOverrides` を coordinator overlay へ置き換える。`items` は repository snapshot の data collection として保持し、descriptor 作成時に effective read/star を合成する。

card star control は `.starred` pending 中 disabled になり、disabled state を accessibility value へ反映する。card 内 star tap は card body selection を発火させない。

Timeline / Feed の item selection は `ArticleDetailSheetInput` を作って `RootView` の detail presentation に渡す。`ArticleDetailSummary` には可能なら `isRead` も持たせ、detail load 前の read baseline として利用する。

### ArticleDetail

`ArticleDetailViewModel` は loaded `ItemDetail` を baseline として保持し、presentation 作成時に coordinator の effective state を合成する。coordinator が同一 item の change を publish した場合、visible presentation を再生成して detail star control と list card を同期させる。

detail open 時の read marking は detail fetch と独立して coordinator flow に乗せる。detail fetch が後から stale `isRead` / `isStarred` を返しても pending optimistic state を上書きしない。

### Search

既存 `GlobalSearchViewModel.applyItemStateChange` は互換経路として残してよい。可能なら Search row descriptor も coordinator effective state を参照する。Search の star mutation UI は現状 disabled のため、本 Issue で新規 star action は追加しない。

Search result open-link の read marking は coordinator flow を使い、失敗時は external open 自体を取り消さず、read optimistic state だけ rollback する。

## Error / accessibility

- read failure: 「既読状態を更新できませんでした。」
- star failure: 「スターを更新できませんでした。」
- auth required: 既存の「再ログインが必要です。」系の handling に委譲する。
- error feedback は primary navigation、scroll、detail dismissal を永続的に塞がない。
- optimistic star state は accessibility selected / unselected と一致させる。
- pending disabled state は VoiceOver でも認識できる label / value / disabled state にする。

## リスク

- `TimelineViewModel` / `FeedViewModel` が `ItemSummary` 配列を直接 mutate する現状の local override と、coordinator overlay が二重管理になると rollback が不正になる。実装では `localStarOverrides` を削除し、effective state 合成に寄せる。
- detail fetch が mutation より後に stale state を返すと、楽観状態を上書きする危険がある。pending / confirmed local value の優先順位で防ぐ。
- 同一 item / field の連打を許すと rollback token の扱いが複雑になる。第一実装では pending 中 disable とする。
- Feed unread count まで更新すると drawer state も巻き込むため、本 Issue では扱わない。

## テスト方針

`FeedmanTests` に coordinator 単体テストを追加し、Feature ViewModel tests は mock repository と dummy token のみで検証する。実ネットワーク、実 Keychain、実 OAuth、個人データは使わない。

重点観点:

- effective state の優先順位。
- star success / failure from card。
- star success / failure from detail。
- read marking success / failure on detail open。
- read failure が star を戻さないこと。
- star failure が read を戻さないこと。
- pending 中の stale refresh が optimistic value を消さないこと。
- same item が list と detail に同時表示される場合の同期。
- pending 中の same field control disabled。
- partial request が read-only / star-only body を維持すること。

## 検証

macOS/Xcode 環境では以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Xcode が利用できない環境では、実行不可理由を実装 PR の結果報告に明記する。
