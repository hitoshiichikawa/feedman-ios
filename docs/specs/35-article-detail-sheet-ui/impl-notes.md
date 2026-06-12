# Issue #35 Article detail sheet UI 実装ノート

## 実装概要

- `Feedman/Features/ArticleDetail/` に `ArticleDetailViewModel` と `ArticleDetailSheet` を追加した。
- sheet は `FeedmanSheetShell` を使い、`.presentationDetents([.medium, .large])` と fixed footer action area を提供する。
- `ArticleDetailViewModel` は `ItemRepository.itemDetail(id:accessToken:)` で詳細を取得し、sheet open 時に `ItemStateUpdateRequest(isRead: true, isStarred: nil)` を送る。
- star toggle は `ItemStateUpdateRequest(isRead: nil, isStarred: <target>)` の partial update とし、成功時は sheet-local state のみ更新する。
- content preview は HTML tag strip と entity decode の簡易レンダで readable text へ変換し、nil / empty の場合は summary または中立文言を表示する。
- `RootView` の timeline / feed / starred の一覧行 tap と search result selection から article detail sheet を開けるようにした。
- 「元記事を開く」は Safari を起動せず、親 callback 経由で placeholder toast を出すだけに留めた。http / https の絶対 URL 以外は disabled 相当になる。
- `AppEnvironment` に `itemRepository` を追加し、production では既存 `APIClient` を使う `FeedmanItemRepository`、preview / tests では mock を使う。

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

## スコープ外として残したこと

- `SFSafariViewController` の presenter 実装。
- detail / list / starred / search をまたぐ global state sync。
- Safari 起動後の既読化 orchestration。
- server API、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype の変更。
