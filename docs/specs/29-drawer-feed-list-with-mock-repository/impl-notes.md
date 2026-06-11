# Issue #29 実装ノート

## 実装内容

- Drawer feed list の source of truth を `FeedRepository.subscriptions()` に変更した。
- `AppShellDrawerFeedViewModel` と `AppShellDrawerFeedSectionState` を追加し、feed section の loading / loaded / empty / failed state を扱うようにした。
- Drawer の global route entry（すべての新着 / お気に入り / アカウント）は feed section の状態に関係なく選択できるまま維持した。
- feed row は repository 由来の title、unread count、stopped / error status label を表示する。
- duplicate feed id でも `ForEach` が落ちないよう、drawer row のレンダリング id は表示順 index にした。route selection には feed の stable `id` を渡す。
- `MockFeedRepository.subscriptions()` に active、unread count あり、stopped、error の mock feed を含めた。
- keyword notification drawer entry、real API integration、subscription settings action は追加していない。

## テスト

- 追加: `FeedmanTests/AppShellDrawerFeedStateTests.swift`
  - mock repository が drawer 表示に必要な title / unread count / status を返すこと。
  - subscription loading success / empty / failure state。
  - failure 時も global route selection が継続できること。
  - failure 時に既存 feed list を保持できること。
  - feed route selection が stable id と title を使うこと。

## 検証結果

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 実行不可。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため `xcodebuild` が実行できない。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 成功。
- `xcrun swiftc -parse Feedman/Core/Models.swift Feedman/Core/FeedRepository.swift Feedman/Features/AppShell/AppShellState.swift Feedman/Features/AppShell/AppShellDrawerFeedState.swift`
  - 成功。
- `xcrun swiftc -typecheck ...`
  - 実行不可。
  - 理由: Command Line Tools 環境では iOS SDK / UIKit module が見つからない。
- `git diff --check`
  - 成功。

## 確認事項

なし。
