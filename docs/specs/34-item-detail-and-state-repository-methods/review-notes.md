# Review Notes

<!-- idd-codex:review round=1 model=gpt-5 timestamp=2026-06-12T07:27:28Z -->

## Reviewed Scope

- Issue: #34 Item detail and state repository methods
- Branch: `codex/issue-34-impl-item-detail-and-state-repository-methods`
- HEAD commit: `d16a3ce4e2175b8aa6f24c943fb7867e4f792ddf`
- Compared to: `develop..HEAD`
- `git diff --stat develop..HEAD` は取得済み。差分は `Feedman/Core/FeedRepository.swift`、`FeedmanTests/ItemRepositoryTests.swift`、`Feedman.xcodeproj/project.pbxproj`、当該 spec の `requirements.md` / `impl-notes.md`。
- `git log --oneline develop..HEAD` は `d16a3ce feat: add item repository detail and state methods` の 1 commit。
- 指定された `tasks.md`、`design.md`、`reviewer.md` は当該 spec directory に存在しなかったため、tasks の `_Requirements:_` / `_Boundary:_` と reviewer 固有契約の照合は実施不能。既存 review-notes 形式、`requirements.md`、`impl-notes.md`、実装差分、テスト差分で判定した。

## Verified Requirements

- 1.1 / 1.2 — `Feedman/Core/FeedRepository.swift:8` 以降で `ItemRepository` が `itemDetail` と `updateItemState` の async methods を提供している。
- 1.3 — `ItemRepository` は `Feedman/Core/FeedRepository.swift` に protocol として追加され、Feature / ViewModel が `FeedmanItemRepository` concrete 型へ直接依存せずに差し替え可能。
- 1.4 — `FeedmanItemRepository` は `APIClient.send` / `sendNoContent` に委譲し、View / ViewModel から `URLSession` を直接扱う差分はない。
- 1.5 — `MockItemRepository` が `ItemRepository` に適合し、後続 ViewModel tests から差し替え可能な configured data / failure / state update 記録を持つ。
- 1.6 / 1.7 — `ItemDetail` は既存 API model の `String` / `String?` fields を利用し、Repository 側で日付変換や favicon 画像化をしていない。
- 2.1 / 2.2 / 2.3 — `FeedmanItemRepository.itemDetail` が `GET /api/items/{id}` を `APIClient` 経由で呼び、Bearer token は APIClient の認証 header 経路へ渡している。`ItemRepositoryTests.swift:8` 以降で method / path / Authorization / decode を検証している。
- 2.4 / 2.5 — detail success response の `content`、`feed_favicon_url`、`published_at`、`hatebu_fetched_at`、`is_read`、`is_starred` は `ItemRepositoryTests.swift:19` 以降で保持を検証している。
- 2.6 / 2.8 — 401 refresh retry と auth-required typed boundary は endpoint 固有処理を足さず `APIClient.performWithRefreshRetry` に委譲している。Requirement 5.9 のとおり repository test suite は #23 の APIClient coverage に依存できる。
- 2.7 — detail fetch の Feedman standard error は `FeedmanAPIError.feedmanError` として `ItemRepositoryTests.swift:84` 以降で typed context を検証している。
- 3.1 / 3.2 — `FeedmanItemRepository.updateItemState` が `PUT /api/items/{id}/state` を `APIClient.sendNoContent` で呼んでいる。
- 3.3 / 3.4 / 3.5 / 3.6 — read-only、star-only、combined partial body は `ItemStateUpdateRequest` の optional fields と Codable synthesis により nil field を省略し、`ItemRepositoryTests.swift:27`、`:47`、`:66` 以降で JSON keys と Boolean 値を検証している。
- 3.7 — `APIResponseDecoder.validateNoContent` は 200..<300 を body decode なしで成功扱いにし、204 と 200 body ありの両方を `ItemRepositoryTests.swift:27` / `:47` 以降で検証している。
- 3.8 — state update の Feedman standard error は `FeedmanAPIError.feedmanError` として `ItemRepositoryTests.swift:102` 以降で typed context を検証している。
- 3.9 — state update の initial 401 も `sendNoContent` から `APIClient.performWithRefreshRetry` に入るため、endpoint 固有 refresh logic は追加されていない。
- 3.10 — optimistic UI update、cross-screen state propagation、rollback orchestration の実装差分はない。
- 4.1 / 4.2 — `MockItemRepository` は configured detail を返し、未設定 id は `MockItemRepositoryError.detailNotFound` で deterministic に失敗する。`ItemRepositoryTests.swift:124` / `:133` 以降で検証している。
- 4.3 / 4.4 / 4.5 — mock state update は item id と partial request を記録し、configured in-memory detail の明示 field のみを更新する。`ItemRepositoryTests.swift:146` 以降で記録と read-only mutation を検証している。
- 4.6 — mock state update failure は configured error を surface し、success 記録を残さないことを `ItemRepositoryTests.swift:164` 以降で検証している。
- 4.7 — mock repository は実 Keychain、OAuth、APIClient、network に依存していない。
- 5.1 / 5.2 / 5.3 — detail fetch の method / path / Bearer header、`content` と RFC3339 string の保持を unit test で検証している。
- 5.4 / 5.5 / 5.6 / 5.7 — read-only、star-only、combined state update body と 2xx success body 非依存を unit test で検証している。
- 5.8 — detail fetch と state update の Feedman error typed context を unit test で検証している。
- 5.9 — 401 refresh retry は #23 の APIClient tests に依存してよい前提で、repository 側に重複 test / logic はない。
- 5.10 — `impl-notes.md:32` 以降に Xcode 本体不在で `xcodebuild` が未実行だった制約が明記されている。
- NFR 1.1 / 1.2 — Swift Concurrency と既存 APIClient / Repository 境界に沿う実装で、View が URLSession / Keychain / request body encoding を扱う差分はない。
- NFR 1.3 — `APIClient`、`ItemDetail`、`ItemStateUpdateRequest`、`FeedmanAPIError` の既存 API layer types を再利用し、endpoint-local JSON model は追加していない。
- NFR 1.4 — Swift 型名、識別子、ファイル名は English。
- NFR 2.1 / 2.2 / 2.3 — 実 token / Secret / 個人情報は見当たらず、tests は dummy token / dummy id のみ。Repository は refresh token を Keychain から直接読まない。
- NFR 3.1 / 3.4 — 実装差分は `Feedman/`、`FeedmanTests/`、Xcode project wiring、当該 spec notes に閉じ、Detail UI、Safari presentation、optimistic sync、list pagination は追加されていない。

## Findings

なし

## Summary

判定カテゴリを `AC 未カバー` / `missing test` / `boundary 逸脱` に限定して確認した。対象差分は空ではなく、repository boundary、real implementation、mock behavior、request construction、typed error propagation、partial body、2xx no-content success の主要 AC は実装・テストで確認できた。`tasks.md`、`design.md`、`reviewer.md` は存在しないため、その範囲は未照合として明記した。

RESULT: approve
