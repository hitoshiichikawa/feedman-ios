# Issue #35 Article detail sheet UI 実装ノート

## 実装概要

- `Feedman/Features/ArticleDetail/` に `ArticleDetailViewModel` と `ArticleDetailSheet` を追加した。
- sheet は `FeedmanSheetShell` を使い、`.presentationDetents([.medium, .large])` と fixed footer action area を提供する。
- `ArticleDetailViewModel` は `ItemRepository.itemDetail(id:accessToken:)` で詳細を取得し、sheet open 時に `ItemStateUpdateRequest(isRead: true, isStarred: nil)` を送る。
- star toggle は `ItemStateUpdateRequest(isRead: nil, isStarred: <target>)` の partial update とし、成功時は sheet-local state のみ更新する。
- content preview は HTML tag strip と entity decode の簡易レンダで readable text へ変換し、nil / empty の場合は summary または中立文言を表示する。
- 親画面から `ArticleDetailSheetInput`、`ItemRepository`、access token、dismiss / open-original callback を受け取る standalone sheet として実装した。
- 「元記事を開く」は Safari を起動せず、親 callback 経由で placeholder toast を出すだけに留めた。http / https の絶対 URL 以外は disabled 相当になる。

## テスト

- `FeedmanTests/ArticleDetailViewModelTests.swift` を追加した。
- 検証観点:
  - open 時に detail fetch と read marking partial request が呼ばれる。
  - detail fetch 失敗時に recoverable state になり、retry が同じ item id で再取得する。
  - read marking 失敗は sheet を閉じず、detail loaded state と non-blocking message を維持する。
  - star toggle 成功時に partial star request を送り、sheet-local state を更新する。
  - star toggle 失敗時に最終 star state を誤表示せず、message を出す。
  - HTML content preview、summary fallback、empty fallback、long content text、invalid original link を検証する。

## 検証結果

- 実行: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- 実行: `git diff --check`
  - 結果: 成功。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 未完了。
  - 理由: この環境の active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求して失敗した。

## レビュー指摘対応

- `develop` 側の内容に合わせ、#35 スコープ外で欠落していた `docs/specs/32-*`、`docs/specs/39-*`、`TimelineView` / `TimelineViewModel` / `TimelineViewModelTests`、`FeedRepository` の #39 pagination / filter API と mock 実装を復元した。
- `RootView` から article detail sheet の直接組み込み、`AppEnvironment.itemRepository` 配線、legacy `crossFeedItems()` 直呼び出しを除去し、authenticated startup は `TimelineViewModel` / `TimelineView` 経由で repository pagination を使う状態へ戻した。
- `AppShellDrawerFeedStateTests` の `testAuthenticatedTimelineStartupDoesNotUseLegacyCrossFeedItems` を復元し、起動時に drawer subscriptions と timeline first page を読み込みつつ legacy `crossFeedItems()` を呼ばないことを検証対象に戻した。
- `Feedman.xcodeproj/project.pbxproj` は Timeline 用 ID と衝突しない ID で ArticleDetail の参照を追加し直した。
- 検証は `plutil -lint Feedman.xcodeproj/project.pbxproj` と `git diff --check` は成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は Xcode 本体がないため実行不可。

## スコープ外として残したこと

- `SFSafariViewController` の presenter 実装。
- detail / list / starred / search をまたぐ global state sync。
- Safari 起動後の既読化 orchestration。
- server API、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype の変更。

## Debugger 経由再実行による是正

### 是正内容

- `FeedmanSheetShell` の `ScrollView` content padding を分解し、fixed footer action area がある場合は bottom padding を 28pt に増やした。footer は overlay ではなく `VStack` 内で `ScrollView` の後続 sibling として配置されるため、footer が scroll content の表示領域に重ならない構造である。今回の変更は、本文最終行と footer divider / action area の視覚的な余白を明示して Requirement 4 AC5 の根拠を補強する。
- `ArticleDetailLoadedContent` の長文 preview は引き続き `Text(...).fixedSize(horizontal: false, vertical: true)` で高さ方向に展開し、外側の `FeedmanSheetShell` の `ScrollView` で medium / large detent の範囲内を scroll する。title / metadata / content preview は同じ scroll content 内の縦積みなので、本文だけが footer の背後へ潜る overlay 構造にはしていない。
- `ArticleDetailViewModelTests.testContentPreviewKeepsLongContentAsReadableText` に、長文 content が preview 生成時に切り詰められないことの assertion を追加した。layout overlap は ViewModel unit test では直接検証できないため、UI snapshot / UI test は今回導入していない。

### Manual verification notes

- iPhone 16 相当: この環境では Xcode 本体 / iOS Simulator による画面起動確認は実施できなかった。代替として、`ArticleDetailSheet` と `FeedmanSheetShell` の SwiftUI layout 構造をコード上で確認した。
- medium detent: `ArticleDetailSheet` は `.presentationDetents([.medium, .large])` を指定している。medium では header と fixed footer が `VStack` の固定領域、本文 preview を含む body が中央の `ScrollView` 領域になり、長文 preview は scroll または large detent への drag により継続閲覧できる構造である。
- large detent: large でも同じ `ScrollView` が利用され、`ArticleDetailLoadedContent` の title / metadata / divider / content preview は縦方向に積まれる。content preview は line limit を持たず、本文末尾まで scroll 可能な構造である。
- narrow width または Dynamic Type 相当: header title / subtitle、記事 title、summary、preview text は `fixedSize(horizontal: false, vertical: true)` を使い、横方向に収まらない場合は縦方向へ伸びる。metadata の author は `lineLimit(1)` と truncation を持ち、dismiss affordance は header 右側の 36pt button として維持される。footer の primary label は button style 側で最大 2 行、44pt 以上の高さを持ち、star control は 44pt touch target を維持する。
- header / metadata / footer / content preview の非重なり: header、scroll content、footer は `VStack(spacing: 0)` の sibling であり、footer は overlay / ZStack ではない。metadata と preview は同じ `VStack` 内で spacing / divider を挟んで配置されるため、本文 preview が metadata や footer に重なる構造ではない。
- footer が最終行を覆わないこと: footer は `ScrollView` 外の後続 sibling としてレイアウトされ、scroll content には footer ありの場合 28pt の bottom padding を設定した。したがって、scroll 最下部では本文最終行の下に余白が残り、fixed footer action area が最終行を覆わないコード構造である。
- 未実施項目: Xcode / Simulator による iPhone 16 medium detent、large detent、narrow width、Dynamic Type 相当の実機相当 visual check は未実施。macOS / Xcode 環境で `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` と Simulator 手動確認を追加で実施する必要がある。

### 再検証結果

- 実行: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- 実行: `git diff --check develop..HEAD`
  - 結果: 成功。
- 実行: `git diff --check`
  - 結果: 成功。未コミットの今回差分にも whitespace error がないことを確認した。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 実行不可。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求して失敗した。
