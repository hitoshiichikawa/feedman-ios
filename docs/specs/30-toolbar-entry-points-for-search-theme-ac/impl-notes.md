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

## Reviewer round 1 reject 是正

- `DrawerView` は header 以外の primary route、feed route、footer action を同一の `ScrollView` に配置し、長い feed 名や大きい Dynamic Type で縦方向の表示量が増えても、footer action が primary navigation items の後でスクロール到達できるようにした。
- drawer footer action label は複数行表示と layout priority を明示し、Dynamic Type で title / subtitle がアイコン、border、他 action と重なりにくい構造にした。
- v1 スコープ外の keyword notification drawer 導線は引き続き追加していない。
- SwiftUI layout と sheet presentation は unit test で意味のある検証が難しいため、以下を manual verification point として残す。
  - Requirement 1 AC8: 長い route title と大きい Dynamic Type で、top toolbar の title が iOS 標準どおり truncation され、検索・テーマ action と重ならないこと。
  - Requirement 5 AC4: drawer open 時、VoiceOver / キーボード操作相当の順序で primary navigation items、feed route items の後に footer action へ到達でき、背後の main content が focus 対象にならないこと。
  - Requirement 5 AC5: Dynamic Type の大きい設定で drawer footer のアカウント、テーマ、フィード登録の label / subtitle が読み取れ、アイコン、badge、border、他 action と重ならないこと。
