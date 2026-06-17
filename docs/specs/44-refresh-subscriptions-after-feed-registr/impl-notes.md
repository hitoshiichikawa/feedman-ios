# Issue #44 実装ノート

## 実装内容

- `AppShellDrawerFeedViewModel.refreshSubscriptionsAfterFeedRegistration(_:repository:)` を追加し、登録成功 feed を drawer state に非破壊で保持してから `FeedRepository.subscriptions()` を再取得するようにした。
- 登録後 refresh 成功時は subscriptions response を drawer feed list の source of truth として反映する。
- 登録後 refresh 失敗時は登録成功自体を失敗扱いにせず、既存 feed と登録 feed を保持した `failed` state に「フィードは登録されましたが、一覧を更新できませんでした」を表示する。
- 通常 reload と登録後 refresh に共通の `loadGeneration` を追加し、複数 reload が重なった場合は最後に開始された reload だけが drawer state を確定するようにした。
- `RootView.completeFeedRegistration(_:)` は登録成功 toast と sheet dismissal を維持しつつ、drawer refresh を別 `Task` で起動する形に変更した。

## テスト追加

- 登録成功後 refresh が `subscriptions()` を呼び、repository 結果を drawer state に反映することを検証した。
- 登録後 refresh 失敗時に登録 feed を保持し、登録成功とは別の retry guidance を `failed` state として出すことを検証した。
- 登録後 refresh 失敗後の retry が subscriptions load path を再実行し、成功時に loaded state へ戻ることを検証した。
- 登録成功イベント由来の reload が重なった場合に、古い完了結果が新しい drawer state を上書きしないことを検証した。
- 登録失敗時は `RegisterFeedViewModel.successEvent` が出ず、subscriptions も呼ばれないことを既存 failure test に追加確認した。

## 検証

- `git diff --check`
  - 結果: 成功。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/AppShellDrawerFeedStateTests -only-testing:FeedmanTests/RegisterFeedViewModelTests test`
  - 結果: 成功。27 tests、0 failures。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 中断。build は進んだが、既存 `AccountViewModelTests.testDuplicateLoadWhileLoadingDoesNotStartSecondRequest` の実行中に出力が止まり、同 test class 単独実行でも同じ箇所で停止したため、ハングした検証プロセスを終了した。

## 確認事項

- 登録成功後に新規 feed route へ自動遷移する挙動は追加していない。
- `POST /api/feeds` と `GET /api/subscriptions` の API 契約、`design/SPEC-iOS.md`、`design/SERVER.md` は変更していない。
- full test suite は今回変更範囲外の `AccountViewModelTests` で停止するため、Reviewer stage では必要に応じて既存テストの状態を別途確認する。

## 是正内容

- Reviewer round=1 の指摘を受け、#44 の責務外だった ArticleDetail / Feeds / Subscriptions / Timeline、Account / Search / Core repository、既存 tests、他 Issue の `docs/specs/*` の削除・後退を `develop` 相当の内容へ戻した。
- #44 の実装差分は `AppShellDrawerFeedViewModel` の登録成功後 subscriptions reload、`RootView.completeFeedRegistration(_:)` からの reload 起動、対応する ViewModel tests に限定した。
- 登録後 reload 失敗時の drawer guidance は登録成功 feedback と分離し、retry は既存 `loadSubscriptions(repository:)` 経由で再実行する形を維持した。
- `docs/specs/44-refresh-subscriptions-after-feed-registr/requirements.md` は変更していない。

## Debugger Fix Plan 対応

- `RegisterFeedSheet` が `RegisterFeedViewModel.successEvent` を `.onChange` で観測し、成功イベント発行時点で AppShell の `onRegistered` callback を一度だけ呼ぶようにした。
- 同じ `RegisterFeedSuccessEvent.id` の二重配送を防ぐ `RegisterFeedSuccessEventDispatcher` を追加した。
- success state の `完了` button は sheet dismissal のみを行うようにし、subscriptions reload の起動点から外した。
- `RootView.completeFeedRegistration(_:)` は登録成功 toast と `AppShellDrawerFeedViewModel.refreshSubscriptionsAfterFeedRegistration(_:repository:)` の `Task` 起動を担当し、sheet dismissal は `完了` / dismiss 操作に任せる形へ変更した。
- `AppShellDrawerFeedStateTests` に、登録成功イベント配送時に `subscriptions()` が呼ばれて drawer state が repository result で更新されること、および同一イベントが二重配送されないことを検証する test を追加した。

## Debugger Fix Plan 検証

- `git diff --check develop..HEAD`
  - 結果: 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FeedmanTests/AppShellDrawerFeedStateTests -only-testing:FeedmanTests/RegisterFeedViewModelTests test`
  - 結果: 成功。30 tests、0 failures。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 成功。298 tests、0 failures。

## Debugger Fix Plan 残課題

- 追加の確認事項はない。
