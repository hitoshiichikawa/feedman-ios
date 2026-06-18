# Issue #37 実装メモ

## Reviewer round=1 reject 是正

- `ItemStateCoordinator` を `Feedman/Core/State` に追加し、app session scoped な read/star effective state、field 単位 pending、commit、rollback、`ItemSummary` / `ItemDetail` / `ItemSearchHit` への合成 helper を実装した。
- Timeline / Feed の card star toggle を coordinator 経由の optimistic update に置き換え、`ItemRepository.updateItemState` の star-only partial request、pending 中 disabled、失敗時 rollback、non-blocking error message を追加した。
- Timeline / Feed から ArticleDetail を開く際、表示中 item の effective read/star を `ArticleDetailSummary` に渡すようにし、detail open 時の read marking baseline が stale にならないようにした。
- ArticleDetail の read marking on open と star toggle を coordinator 経由に変更し、detail / visible list copy の同期、repository success commit、failure rollback、field-specific error message を追加した。
- GlobalSearch の表示中 hit と search result open-link read marking を coordinator に接続し、既存 `applyItemStateChange` 互換経路は維持した。
- `ItemStateCoordinatorTests` と ViewModel tests を追加・更新し、effective state priority、pending stale refresh、field-specific rollback、Timeline / Feed star success/failure、ArticleDetail read/star rollback と共有 coordinator 反映を検証した。

### 検証

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: この環境の active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。`xcodebuild` が Xcode ではなく Command Line Tools を指しており、iOS Simulator test を起動できなかった。

### 確認事項

- 追加の PM 確認事項はなし。

## Reviewer round=2 reject 是正

- Debugger の Fix Plan に従い、Timeline card 起点の star success / failure について、同一 `ItemStateCoordinator` を共有する Timeline card descriptor と ArticleDetail loaded presentation の双方が同時に更新 / rollback される ViewModel tests を追加した。
- ArticleDetail open 時の read marking success について、ArticleDetail presentation と同一 coordinator 経由の visible list copy effective state がどちらも read になる ViewModel test を追加した。
- 追加した success test では star-only / read-only の `ItemStateUpdateRequest` も検証し、既存の partial request 期待値と整合させた。

### 検証

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `git diff --check`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: この環境の active developer directory が `/Library/Developer/CommandLineTools` のため実行不可。`xcodebuild` が Xcode ではなく Command Line Tools を指しており、iOS Simulator test を起動できなかった。

### 確認事項

- 追加の PM 確認事項はなし。
