# Issue #30 実装メモ

## 実装概要

- `AppShellState` に `activePresentation` と `themeOverride` を追加し、検索 route activation、アカウント sheet、フィード登録 sheet、テーマ切替を明示 state helper 経由で扱うようにした。
- top toolbar は既存のメニューと title を維持し、trailing actions として検索とテーマ切替を表示する。検索 tap は `.search` route を選択し、テーマ tap は `system -> dark -> light -> system` の順で現在セッション内の表示 override を切り替える。
- drawer footer は primary route / feed list から分離し、アカウント、テーマ、フィード登録の entry point を表示する。keyword notification の導線は追加していない。
- アカウントとフィード登録は単一の `activePresentation` による placeholder sheet とし、`FeedmanSheetShell` を使ってタイトル、説明、dismiss control を表示する。実ユーザーデータ、ログアウト、退会、登録 API、ネットワーク送信は実装していない。
- テーマ override は `preferredColorScheme` に接続し、toolbar と drawer footer で同じ `AppShellThemeOverride` を使う。永続化は実装していない。

## テスト

- `FeedmanTests/AppShellStateTests.swift` に以下の state helper 検証を追加した。
  - 検索 route activation と drawer close
  - 検索 route 再 activation 時の単一路線維持と presentation clear
  - アカウント presentation state と drawer close
  - フィード登録 presentation state と既存 presentation の置換
  - presentation dismiss
  - theme override の `system -> dark -> light -> system` 遷移
  - theme override が route / drawer state を変更しないこと
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行したが、現在の developer directory が `/Library/Developer/CommandLineTools` で Xcode.app が利用できないため失敗した。

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

## 確認事項

- Xcode が利用できる環境で、toolbar の検索・テーマ action、drawer footer のアカウント・テーマ・フィード登録 action、placeholder sheet の dismiss、light/dark/system 表示反映を手動確認する。
- アカウントは既存 route enum を残しているが、今回追加した drawer footer entry point は sheet presentation を使う。後続 Issue で account 本実装の画面形態が確定した場合に route / sheet の整理を検討する。
