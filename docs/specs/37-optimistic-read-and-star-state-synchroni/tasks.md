# Issue #37 Optimistic read and star state synchronization タスク分割

## 1. Core/State coordinator

- [ ] `Feedman/Core/State/ItemStateCoordinator.swift` を追加する。
- [ ] `ItemStateCoordinator` を `@MainActor ObservableObject` として実装する。
- [ ] item id / field 単位の pending optimistic value、confirmed local value、rollback previous value、mutation token を保持する。
- [ ] `ItemStateField`、`ItemStateSnapshot`、mutation token metadata を定義する。
- [ ] `ItemSummary` / `ItemDetail` / `ItemSearchHit` へ effective read/star を合成する helper を用意する。
- [ ] pending 中の same item / same field を判定する API を用意する。
- [ ] repository refresh data が pending optimistic value を消さないようにする。
- [ ] confirmed local value を session scoped に保持し、server data と一致した field は prune 可能にする。

## 2. Coordinator tests

- [ ] `FeedmanTests/ItemStateCoordinatorTests.swift` を追加する。
- [ ] repository value に overlay がない場合は base read/star を返すことを検証する。
- [ ] pending optimistic value が base より優先されることを検証する。
- [ ] mutation success 後に confirmed local value が visible state として残ることを検証する。
- [ ] mutation failure が token 一致時だけ rollback することを検証する。
- [ ] read failure が star state を戻さないことを検証する。
- [ ] star failure が read state を戻さないことを検証する。
- [ ] pending 中の stale refresh が optimistic value を上書きしないことを検証する。
- [ ] same item / same field pending 判定が true になることを検証する。

## 3. Root wiring

- [ ] `RootView` に app-session scoped な `@StateObject private var itemStateCoordinator` を追加する。
- [ ] Timeline / Feed / ArticleDetail / Search / open-link coordinator へ `itemStateCoordinator` を注入する。
- [ ] `shellState.itemStateChange` だけに依存した伝播を coordinator 中心の伝播へ整理する。
- [ ] mutation failure の toast は既存 `FeedmanToastCenter` を使う。
- [ ] global singleton は追加しない。

## 4. Timeline integration

- [ ] `TimelineViewModel.localStarOverrides` を削除し、effective state は coordinator から合成する。
- [ ] `TimelineCardDescriptor` が effective `isRead` / `isStarred` / pending state を受け取れるようにする。
- [ ] card star toggle を optimistic star mutation flow に接続する。
- [ ] star-only mutation request が `is_starred` だけを送ることを保つ。
- [ ] star pending 中は同一 item の star control を disabled にする。
- [ ] card star tap が card body selection を発火しないことを維持する。
- [ ] card selection から ArticleDetail sheet を開く wiring を追加する。
- [ ] Timeline tests に star success / failure / rollback / disabled を追加する。

## 5. Feed integration

- [ ] `FeedViewModel.localStarOverrides` を削除し、Timeline と同じ coordinator effective state を使う。
- [ ] `FeedItemCardDescriptor` が effective read/star と pending state を反映するようにする。
- [ ] feed item card star toggle を optimistic star mutation flow に接続する。
- [ ] feed item selection から ArticleDetail sheet を開く wiring を追加する。
- [ ] filter 表示中の rollback が visible collection に反映されることを ViewModel test で確認する。
- [ ] feed unread count は変更しない。

## 6. ArticleDetail integration

- [ ] `ArticleDetailViewModel` に `ItemStateCoordinator` を注入する。
- [ ] `ArticleDetailSummary` に nullable `isRead` を追加し、detail load 前の baseline に使う。
- [ ] detail open 時の read marking を coordinator optimistic flow に接続する。
- [ ] detail star toggle を coordinator optimistic flow に接続する。
- [ ] loaded `ItemDetail` から presentation を作る際に effective read/star を合成する。
- [ ] coordinator change を受けて visible detail presentation を再生成する。
- [ ] read failure は sheet を dismiss せず message / toast を表示する。
- [ ] star failure は star field だけ rollback し message / toast を表示する。
- [ ] ArticleDetail tests に read success / failure、star success / failure、list-detail sync を追加する。

## 7. Search / open-link integration

- [ ] `GlobalSearchViewModel.applyItemStateChange` の既存互換を維持する。
- [ ] Search row descriptor が coordinator effective state を利用できる場合は接続する。
- [ ] Search result open-link read marking を coordinator optimistic flow に接続する。
- [ ] open-link read marking failure では external open を取り消さず、read optimistic state だけ rollback する。
- [ ] Search tests に read marking success / failure と rollback を追加する。
- [ ] Search star action は新規追加しない。

## 8. UI feedback / accessibility

- [ ] read failure message は「既読状態を更新できませんでした。」相当にする。
- [ ] star failure message は「スターを更新できませんでした。」相当にする。
- [ ] auth required は既存 auth handling と toast に委譲する。
- [ ] disabled star control の accessibility state を確認する。
- [ ] optimistic star selected state が accessibility と一致することを確認する。
- [ ] read opacity 以外に既存 accessibility value がある場合は optimistic read を反映する。
- [ ] light / dark / narrow width / Dynamic Type で action overlap がないことを手動確認する。

## 9. Repository contract verification

- [ ] read-only mutation が `ItemStateUpdateRequest(isRead: true, isStarred: nil)` を送ることを検証する。
- [ ] star-only mutation が `ItemStateUpdateRequest(isRead: nil, isStarred: target)` を送ることを検証する。
- [ ] server response body を要求しないことを維持する。
- [ ] View / ViewModel が `URLSession` や Keychain を直接扱わないことを確認する。
- [ ] endpoint-specific token refresh logic を追加しない。

## 10. Final verification

- [ ] `FeedmanTests` の coordinator / ViewModel tests を追加または更新する。
- [ ] `plutil -lint Feedman.xcodeproj/project.pbxproj` を実行する。
- [ ] `git diff --check` を実行する。
- [ ] macOS/Xcode 環境で以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- [ ] Xcode が利用できない場合は、実行不可理由を実装 PR の結果報告に明記する。
