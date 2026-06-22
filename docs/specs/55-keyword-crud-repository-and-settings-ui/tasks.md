# Implementation Plan

- [x] 1. Keyword API model と repository contract を追加する
  - `Feedman/Core/APIModels.swift` に `KeywordResponse`、`KeywordCreateRequest`、`KeywordUpdateRequest` を追加する。
  - `Feedman/Core/KeywordRepository.swift` に `KeywordRepository` protocol、`APIClientKeywordRepository`、`MockKeywordRepository` を追加する。
  - GET/POST/PATCH/DELETE の method/path/body/Bearer header と 401 refresh retry 委譲を `KeywordRepositoryTests` で検証する。
  - API model decode/encode が `id`、`term`、`scope`、`enabled`、`hits` を保持することを検証する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 7.1, 7.2, 7.3, 7.6_
  - _Boundary: KeywordAPIModels, KeywordRepository_

- [x] 2. AppEnvironment に keyword repository dependency を接続する
  - `AppEnvironment` に `keywordRepository` を injectable dependency として追加する。
  - production wiring では既存 `APIClient` と access token refresh hook を共有する `APIClientKeywordRepository` を渡す。
  - preview/test wiring では `MockKeywordRepository` を渡し、既存 preview が実ネットワークへ依存しないことを保つ。
  - 新規 Swift files を `Feedman.xcodeproj` の app/test target に追加し、project file の整合を保つ。
  - _Requirements: 2.6, 2.8, 7.1, 7.6, 8.5, 8.6, 8.7_
  - _Boundary: KeywordRepository, AppShellKeywordSettingsPresentation_
  - _Depends: 1_

- [x] 3. KeywordSettingsViewModel の state machine と error mapping を実装する
  - `Feedman/Features/Notifications/KeywordSettingsViewModel.swift` を追加し、initial load、retry、create、edit、toggle、delete confirmation を扱う。
  - Empty/whitespace term の repository call 抑止、trim、duplicate in-flight guard を実装する。
  - Duplicate / rate-limit / auth-required / network / generic error presentation を feature-local に実装する。
  - ViewModel tests で loading、success、empty、initial error retry、mutation success、mutation failure preservation、duplicate action guard、delete confirmation を検証する。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.4, 7.5, 7.6, 8.4_
  - _Boundary: KeywordSettingsViewModel_
  - _Depends: 1_

- [x] 4. KeywordSettingsSheet UI を追加する
  - `Feedman/Features/Notifications/KeywordSettingsSheet.swift` を追加し、`FeedmanSheetShell`、`FeedmanTheme`、loading/empty/error/banner primitives を再利用する。
  - Keyword term、enabled toggle、hits count、add/edit/delete controls を ViewModel に接続する。
  - Operation in-flight 中の control disabled/progress 表示、long keyword、Dynamic Type、VoiceOver label を実装する。
  - Sheet preview または lightweight UI state coverage を追加し、実ネットワークや実 token に依存しないことを確認する。
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 8.1, 8.2, 8.3, 8.4, 8.5, 8.7_
  - _Boundary: KeywordSettingsSheet_
  - _Depends: 3_

- [x] 5. AppShell から keyword settings sheet を開く
  - `AppShellPresentation.keywordSettings` と `presentKeywordSettings()` を追加する。
  - Drawer/footer に既存 visual pattern と整合する「キーワード通知」entry point を追加し、tap で drawer を閉じて sheet を表示する。
  - `RootView.sheetContent` に `KeywordSettingsSheet` を接続し、`environment.keywordRepository` と `environment.currentAccessToken` を渡す。
  - AppShell state tests で presentation、dismiss 後の current route preservation、既存 route behavior の不変性を検証する。
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 8.5, 8.6, 8.7_
  - _Boundary: AppShellKeywordSettingsPresentation, KeywordSettingsSheet_
  - _Depends: 2, 4_

- [x] 6. Cross-boundary regression と scope guard を補強する
  - Keyword settings の auth-required callback / toast guidance が silent failure にならないことをテストまたは既存 pattern で確認する。
  - Timeline、Feed、Starred、Search、ArticleDetail、Account、Subscription の既存 behavior を変更していないことを差分レビューで確認する。
  - `/api/devices`、APNs token、logout unregister policy に変更を入れていないことを確認する。
  - Server worker、push delivery、notification deep link、body/content matching、OPML、feed-scoped search を追加していないことを差分レビューで確認する。
  - _Requirements: 6.4, 6.5, 8.4, 8.5, 8.6, 8.8_
  - _Boundary: AppShellKeywordSettingsPresentation, KeywordSettingsViewModel_
  - _Depends: 5_

- [ ] 7. 最終検証を実行し、未確認 API 契約を PR で報告する
  - `plutil -lint Feedman.xcodeproj/project.pbxproj` を実行する。
  - `git diff --check` を実行する。
  - macOS/Xcode 環境で `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` を実行する。実行できない場合は理由を PR に記載する。
  - `GET /api/keywords` / `POST` / `PATCH` の response shape と duplicate error code の確認結果または未確認事項を PR の「確認事項」に残す。
  - _Requirements: 1.6, 2.7, 7.2, 7.3, 7.4, 7.5, 7.6, 8.6, 8.8_
  - _Boundary: KeywordAPIModels, KeywordRepository, KeywordSettingsViewModel, KeywordSettingsSheet, AppShellKeywordSettingsPresentation_
  - _Depends: 1, 2, 3, 4, 5, 6_

## Verify

本 spec の実装後、watcher（stage-a-verify gate）が再実行すべき verify コマンドを構造化ブロックで宣言する。

<!-- stage-a-verify -->
```sh
plutil -lint Feedman.xcodeproj/project.pbxproj &&
git diff --check &&
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```
