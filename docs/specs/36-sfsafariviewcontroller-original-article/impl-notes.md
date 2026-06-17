# Issue #36 SFSafariViewController original article opener 実装ノート

## 実装概要

- `Feedman/Features/ArticleDetail/ArticleDetailSafariView.swift` を追加し、`SFSafariViewController` を SwiftUI から表示する薄い `UIViewControllerRepresentable` にした。
- `ArticleDetailSheet` は「元記事を開く」押下時に `ArticleDetailViewModel.openOriginal()` を呼び、返却された URL を nested sheet の `ArticleDetailSafariView` で表示する。
- `RootView` の ArticleDetail 用 `onOpenOriginal` から SwiftUI `openURL` 直結を削除した。Timeline / Feed / Search の既存 `openURL` 経路は本 Issue の範囲外として変更していない。
- `ArticleDetailViewModel` に `ArticleDetailOriginalArticleRequest` と `openOriginal()` を追加した。URL は http / https かつ host ありのみ有効とし、loaded detail の link を summary link より優先する。
- invalid / missing / non-http(s) URL では Safari を表示せず、`元記事のURLを開けませんでした。` を recoverable message として出す。invalid URL の場合は read marking を要求しない。
- 「元記事を開く」button は invalid URL でも押下時に recoverable error を出すため、URL 不正だけでは disabled にしない。Safari presentation は ViewModel が返す validated request がある場合に限る。
- open-original 時に sheet-open 既読化が未成功なら `ItemRepository.updateItemState(id, ItemStateUpdateRequest(isRead: true, isStarred: nil), accessToken:)` を retry する。既に sheet-open 既読化が成功している場合は重複 mutation を skip する。
- read marking 失敗時も Safari 表示 intent は返し、`既読状態を保存できませんでした。` または既存 auth-required 文言を non-blocking message / auth boundary へ流す。

## テスト

- `FeedmanTests/ArticleDetailViewModelTests.swift` に open-original の検証を追加した。
- 追加検証:
  - valid http URL で Safari presentation intent 相当の request を返し、`isRead == true` / `isStarred == nil` の partial request を送る。
  - valid https URL で request を返す。
  - loaded detail の URL を summary URL より優先する。
  - blank / malformed / ftp URL では request を返さず、recoverable message を出し、read marking を送らない。
  - read marking 失敗でも URL request を返し、read failure message を保持する。
  - access token missing / auth-required failure は既存 auth-required boundary に流す。

## 検証結果

- 実行: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- 実行: `git diff --check`
  - 結果: 成功。
- 実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 実行不可。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求して失敗した。

## オーケストレーター確認での追加修正

- invalid URL の場合にも「元記事を開く」押下で recoverable error を表示するよう、footer button は URL 不正だけでは disabled にしない形へ調整した。Safari は validated request が返った場合のみ表示するため、invalid URL で `SFSafariViewController` は起動しない。
- 再実行: `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 結果: 成功。
- 再実行: `git diff --check`
  - 結果: 成功。
- 再実行: `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 実行不可。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、`xcodebuild` が Xcode 本体を要求して失敗した。

## スコープ外として残したこと

- detail / list / starred / search をまたぐ global state sync の大規模拡張。
- 外部ブラウザ preference や `UIApplication.open` への切替設定。
- Timeline / Feed / Search の既存 link open flow の置き換え。
- `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、他 Issue の確定済み specs の変更。
