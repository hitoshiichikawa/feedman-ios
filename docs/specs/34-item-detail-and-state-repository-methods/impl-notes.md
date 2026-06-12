# 実装ノート

## 実装内容

- `Feedman/Core/FeedRepository.swift` に `ItemRepository` protocol を追加した。
- `FeedmanItemRepository` を追加し、既存 `APIClient` 経由で以下を呼び出すようにした。
  - `GET /api/items/{id}`: `ItemDetail` を decode して返す。
  - `PUT /api/items/{id}/state`: `ItemStateUpdateRequest` を body として送り、2xx を body decode なしで成功扱いにする。
- `MockItemRepository` を追加し、設定済み `ItemDetail` の返却、未設定 detail の deterministic error、state update request の記録、設定済み detail の明示 field のみの in-memory 更新に対応した。
- `FeedmanTests/ItemRepositoryTests.swift` を追加し、request method / path / Bearer header / partial body / typed error propagation / mock behavior を検証する test を追加した。
- 新規 test file を Xcode test target に含めるため `Feedman.xcodeproj/project.pbxproj` を更新した。

## 判断事項

- `ItemRepository` method は現状の `AppAuthenticationState.authenticated(accessToken:)` と `APIClient` の `accessToken` parameter に合わせ、`accessToken` を引数で受け取る形にした。
- state update は read / star 個別 method ではなく、`ItemStateUpdateRequest` を受け取る combined partial update method とした。`nil` field は `Codable` synthesis により JSON body から省略される。
- `PUT /api/items/{id}/state` は成功 response body を要求せず、`APIClient.sendNoContent` に委譲して任意の 2xx を成功として扱う。
- 401 refresh retry、auth-required typed boundary、Feedman standard error の変換は endpoint 固有処理を追加せず、既存 `APIClient` に委譲した。
- Detail UI、SFSafariViewController presenter、optimistic cross-screen sync は実装していない。

## 実行した検証

- `git diff --check`
  - 成功。
- `plutil -lint Feedman.xcodeproj/project.pbxproj`
  - 成功。
- `xcrun swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Models.swift Feedman/Core/FeedRepository.swift`
  - 成功。
- `xcrun swiftc -parse FeedmanTests/ItemRepositoryTests.swift`
  - 成功。

## 実行できなかった検証

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 未実行。
  - 理由: active developer directory が `/Library/Developer/CommandLineTools` で、Xcode 本体ではないため `xcodebuild` が `tool 'xcodebuild' requires Xcode` で終了した。

## 確認事項

- `PUT /api/items/{id}/state` は requirements の前提どおり 2xx を成功として扱い、updated item response body は要求していない。
- production `AppEnvironment` への item repository wiring は、refresh hook を含む application-wide APIClient wiring と一緒に扱う必要があるため、本 Issue では repository boundary と implementation の追加に留めた。
