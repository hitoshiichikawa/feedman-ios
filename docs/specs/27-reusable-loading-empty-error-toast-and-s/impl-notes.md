# Issue #27 実装ノート

## 実装内容

- `Feedman/DesignSystem/SharedPrimitives.swift` に loading、compact loading row、empty state、recoverable error state、toast/banner、native sheet shell helper を追加した。
- 各 primitive は `FeedmanTheme` の semantic token を利用し、feature 固有の API error 判定や business logic は持たせていない。
- Sheet は SwiftUI native `.sheet` と `.presentationDetents([.medium, .large])` を使う `feedmanSheet` helper と、直接利用できる `FeedmanSheetShell` を用意した。
- UI snapshot infrastructure は未導入のため追加していない。layout の詳細は SwiftUI preview と実機/Simulator で確認する前提とした。

## Toast の挙動

Toast は deterministic replacement behavior を採用した。

- `FeedmanToastCenter.show(_:)` が呼ばれるたびに現在の toast を即時置換する。
- 既存 toast の dismissal task は cancel し、新しい toast の duration だけを有効にする。
- 呼び出し側は ad hoc timer を持たず、`FeedmanToastCenter` に message/style/duration を渡すだけでよい。
- `duration <= 0` の toast は自動 dismiss せず、呼び出し側または画面遷移時の `dismiss()` で閉じる。

## テスト

- `FeedmanTests/FeedmanTests.swift` に `FeedmanToastCenter` の replacement と manual dismiss の unit test を追加した。
- auto-dismiss の実時間待ちは brittle になりやすいため、今回の unit test では対象外とした。
- 作業環境は active developer directory が `/Library/Developer/CommandLineTools` で Xcode.app が無いため、`xcodebuild` は実行不能だった。代替として `plutil -lint Feedman.xcodeproj/project.pbxproj` と Swift parser による構文確認を実行した。

## 手動確認ポイント

- Loading / compact loading row が Dynamic Type で重ならないこと。
- Empty / recoverable error state の長い日本語 subtitle が container 内で折り返されること。
- Toast overlay が画面操作を block せず、長文でも 3 行までの範囲で重ならないこと。
- Banner の action あり/なしで不要な control area が残らないこと。
- Sheet shell の header/dismiss が scroll content に隠れず、primary action あり/なしで action bar の有無が切り替わること。
- Light/Dark mode で `FeedmanTheme` token に沿って表示されること。

## Reviewer reject 是正

- AC 6.2 対応として `FeedmanSheetShell` の dark mode preview を追加した。`Shared Primitives Dark` にも compact loading row を含め、sheet header、content、action bar、loading row の代表状態を light/dark 双方で確認できるようにした。

## 確認事項

- Toast は queue ではなく replacement として確定した。連続メッセージを順番に見せる要件が後続 Issue で出た場合は、`FeedmanToastCenter` の内部 policy を queue に差し替える。
- Banner は inline status view として toast とは別 view にした。style enum は toast と共有し、endpoint 固有の action 判定は呼び出し側に残す。
- Sheet shell の action bar は単一 primary action を想定した。複数 action や destructive action の配置規約が必要になった場合は、後続 Issue で拡張する。
- この作業環境では Xcode.app が無く `xcodebuild` 検証を完走できなかった。Xcode 環境では `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` の実行が必要。
