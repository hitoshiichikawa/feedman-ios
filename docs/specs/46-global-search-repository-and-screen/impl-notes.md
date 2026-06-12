# Issue #46 Global search repository and screen 実装メモ

## 実装内容

- `Feedman/Core/SearchRepository.swift` を追加し、`SearchRepository` protocol、`APIClientSearchRepository`、`MockSearchRepository`、`SearchScope` を定義した。
- real repository は `GET /api/items/search` に `q=<query>` と `scope=<scope>` を `URLQueryItem` で渡し、共有 `APIClient` の認証付き request / refresh retry behavior を利用する。
- response は `ItemSearchHit` 配列として decode し、`ItemSummary` への変換は行わない。
- `Feedman/Features/Search` に `GlobalSearchViewModel` と `GlobalSearchView` を追加した。
- 空文字または空白のみの query は ViewModel で停止し、repository / transport に request を送らない。
- submit ごとに request id を更新し、古い response が新しい query の表示を上書きしないようにした。
- `publishedAt == nil` は日付表示を省略し、`faviconURL == nil` または `data:` URL は既存 `FeedmanFaviconView` 経由で扱う。
- 検索結果カードでは既存の `ArticleSourceRow`、`ArticleStarControl`、`ArticleOpenLinkControl`、`ArticleHatebuCountControl` を利用した。検索結果には `hatebu_fetched_at` が無いため、はてブ状態は unavailable として表示する。
- AppShell の `.search` route placeholder を `GlobalSearchView` に置き換えた。
- `AppEnvironment` に access token から search repository を作る factory を追加し、production では refresh hook 付き `APIClientSearchRepository`、preview/default では mock を返す。

## テスト

- `FeedmanTests/SearchRepositoryTests.swift` を追加した。
  - 非空 query で path `/api/items/search`、query items `q` / `scope=global`、Bearer token が送られることを検証した。
  - 日本語、空白、予約文字を含む query が `URLQueryItem` 経由で保持され、不正な URL にならないことを検証した。
  - auth-required error が空結果ではなく typed error として伝播することを検証した。
- `FeedmanTests/GlobalSearchViewModelTests.swift` を追加した。
  - 初期状態、空/空白 query no-request、loading から success、empty、error、retry、auth-required boundary、古い response の破棄、suggestion submit を検証した。
  - nullable `publishedAt`、`data:` favicon、`hatebu_fetched_at` 不在、card select と open-link action 境界を descriptor で検証した。

## 実行した検証

```bash
xcrun swiftc -parse Feedman/Core/SearchRepository.swift Feedman/Features/Search/GlobalSearchViewModel.swift Feedman/Features/Search/GlobalSearchView.swift FeedmanTests/SearchRepositoryTests.swift FeedmanTests/GlobalSearchViewModelTests.swift
```

結果: 成功。

```bash
plutil -lint Feedman.xcodeproj/project.pbxproj
```

結果: `Feedman.xcodeproj/project.pbxproj: OK`。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

結果: 実行不可。active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため `xcodebuild` が実行できなかった。

## 確認事項

- 既存コードには article detail coordinator / sheet presentation がまだ無いため、検索結果 card tap は `onSelectItem` callback 境界までの実装に留めた。
- 既存コードには `SFSafariViewController` presentation 境界がまだ無いため、open-link は AppShell から SwiftUI `openURL` に委譲している。SFSafari 境界が確定した時点で差し替えが必要。
- access token refresh 成功後に `AppAuthenticationState` の access token を更新する共通経路はまだ無いため、search repository factory は現在の authenticated access token を初期 request に使い、401 時の retry は共有 `APIClient` の refresh hook に委譲している。
