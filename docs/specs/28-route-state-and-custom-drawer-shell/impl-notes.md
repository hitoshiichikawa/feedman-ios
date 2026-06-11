# Issue #28 実装ノート

## 実装内容

- `AppShellRoute` と `AppShellState` を追加し、現在 route、toolbar title、drawer selection を同じ source of truth から導出するようにした。
- drawer open state は `AppShellState.isDrawerOpen` として route とは独立して保持した。
- menu button で drawer と scrim を表示し、scrim tap または drawer header の閉じる button で drawer のみを閉じるようにした。
- drawer route 選択時は drawer を閉じ、選択 route に更新する。同一 route 選択時も drawer は閉じる。
- drawer の feed entries は AppShell 内の placeholder data に限定し、real subscriptions API integration は追加していない。
- `検索` と `アカウント` は明示 route として扱い、この Issue では placeholder surface のみ表示する。
- v1 scope 外のキーワード通知 UI と drawer 導線は追加していない。

## テスト

- `FeedmanTests/AppShellStateTests.swift` を追加し、default route、dismiss behavior、drawer route selection、feed id / title 分離、unknown feed fallback title、同一 route 選択時の close behavior を検証する単体テストを追加した。
- `plutil -lint Feedman.xcodeproj/project.pbxproj` は成功した。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は実行できなかった。理由は active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため。

## 手動確認ポイント

- menu button tap で左 drawer と scrim が表示され、main content が右へ offset すること。
- scrim tap と drawer header の閉じる button で drawer が閉じ、現在 route が変わらないこと。
- drawer の `すべての新着`、`お気に入り`、feed entries、`アカウント` 選択で drawer が閉じ、toolbar title と selected state が更新されること。
- search toolbar button tap で `検索` route に切り替わること。
- drawer を閉じた状態で scrim と hidden drawer controls が touch / accessibility focus を奪わないこと。

## 確認事項

- 追加確認が必要な未決事項はない。
