# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-17T08:14:28Z -->

## Reviewed Scope

- Branch: codex/issue-36-impl-sfsafariviewcontroller-original-article
- HEAD commit: 69df2125e860978a16c8b7c6accad7d7f63a4f25
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `ArticleDetailSheet.swift:43` / `ArticleDetailSheet.swift:76` で valid URL request を `ArticleDetailSafariView` sheet に渡して表示する。
- 1.2 — `ArticleDetailSafariView.swift:1` / `ArticleDetailSafariView.swift:17` で `SafariServices.SFSafariViewController` を生成し、ArticleDetail 経路の `openURL` 直結は `RootView.swift` 差分で削除済み。
- 1.3 — Safari は ArticleDetail sheet 内の nested sheet state として保持され、dismiss 後に AppShell route state を消す処理は追加されていない。
- 1.4 — `ArticleDetailSafariPresentation` の `id` が `itemID + url.absoluteString` で、別 URL は別 presentation intent になる。
- 1.5 — Safari presentation state は ArticleDetail sheet の `safariPresentation` に閉じ、account / feed registration / subscription settings の state 変更は追加されていない。
- 1.6 — 外部ブラウザ preference / browser selection setting の追加なし。
- 2.1 — `ArticleDetailFooter` の action を `ArticleDetailSheet` が受け、`ArticleDetailViewModel.openOriginal()` の request を Safari presenter state に接続している。
- 2.2 — `ArticleDetailOriginalArticleRequest.itemID` が read marking と Safari presentation の item context を保持する。
- 2.3 — `ArticleDetailViewModel.originalArticleURL` は loaded `detail.link` を summary link より優先し、`testOpenOriginalPrefersLoadedDetailURLOverSummaryURL` で検証済み。
- 2.4 — detail 未ロード時は summary link を validation 後に使用し、invalid / non-http(s) は request を返さない。
- 2.5 — invalid URL では `openOriginalInvalidURL` の recoverable message を出し、Safari presentation state を作らない。
- 2.6 — ArticleDetail View は `URLSession` / Keychain / token refresh を直接扱わず、read marking は `ItemRepository` 経由。
- 2.7 — 既存の `ArticleDetailSheet` / `ArticleDetailViewModel` / summary state を拡張しており、重複 detail feature は追加されていない。
- 3.1 — `openOriginal()` は必要時に `markReadOnOpen()` を呼び、`ItemRepository.updateItemState` を実行する。
- 3.2 — `ItemStateUpdateRequest(isRead: true, isStarred: nil)` を送ることを `testOpenOriginalWithValidHTTPURLReturnsRequestAndMarksRead` で検証済み。
- 3.3 — `didMarkReadOnOpen` が true の場合は open-original 側の重複 mutation を skip し、未読化 request は送らない。
- 3.4 — read marking 成功時に `ItemStateChange(itemID:isRead:true,isStarred:nil)` を emit し、同テストで検証済み。
- 3.5 — read marking failure でも URL request を返し、message を保持することを `testOpenOriginalReadMarkingFailureStillReturnsURLAndKeepsMessage` で検証済み。
- 3.6 — missing token / auth-required failure は `onAuthRequired` へ流し、`testOpenOriginalMissingAccessTokenRoutesAuthBoundary` と `testOpenOriginalAuthRequiredFailureRoutesAuthBoundary` で検証済み。
- 3.7 — 新しい item state API や updated item body 前提は追加されていない。
- 4.1 — missing / blank / malformed / non-http(s) URL では `validHTTPURL` が nil を返し、Safari presentation を作らない。
- 4.2 — affordance は invalid 時でも押下可能だが、accessibility hint で unavailable 相当を伝え、押下後 recoverable error に誘導する。
- 4.3 — invalid trigger 時の message は `元記事のURLを開けませんでした。`。
- 4.4 — invalid URL message は ArticleDetail body banner として表示され、sheet dismissal / retry UI を壊す変更はない。
- 4.5 — invalid URL では `openOriginal()` が早期 return し、read marking を要求しないことを `testOpenOriginalWithInvalidURLReturnsNilAndDoesNotMarkRead` で検証済み。
- 4.6 — テスト URL は `example.com` と dummy string のみ。
- 5.1 — valid URL preparation failure の追加 failure path はないが、URL preparation は ViewModel validation に集約され、invalid preparation は recoverable message になる。
- 5.2 — read marking failure message は `既読状態を保存できませんでした。`。
- 5.3 — auth-required message は既存の再ログイン文言と `onAuthRequired` boundary に流れる。
- 5.4 — feedback は既存 `FeedmanBannerView` で dismiss 可能。
- 5.5 — shared banner primitive を再利用している。
- 5.6 — user-visible message に raw backend payload / token / Authorization header は含まれていない。
- 6.1 — valid http URL の presentation intent は `testOpenOriginalWithValidHTTPURLReturnsRequestAndMarksRead` で検証済み。
- 6.2 — valid https URL の presentation intent は `testOpenOriginalWithValidHTTPSURLReturnsRequest` で検証済み。
- 6.3 — invalid / unsupported scheme の no-presentation intent と recoverable error は `testOpenOriginalWithInvalidURLReturnsNilAndDoesNotMarkRead` で検証済み。
- 6.4 — `isRead == true` / `isStarred == nil` の repository request は `testOpenOriginalWithValidHTTPURLReturnsRequestAndMarksRead` で検証済み。
- 6.5 — confirmed read signal は同テストの `stateChanges` assertion で検証済み。
- 6.6 — read marking failure でも request が返り、message が残ることを `testOpenOriginalReadMarkingFailureStillReturnsURLAndKeepsMessage` で検証済み。
- 6.7 — auth missing / expired route は `testOpenOriginalMissingAccessTokenRoutesAuthBoundary` と `testOpenOriginalAuthRequiredFailureRoutesAuthBoundary` で検証済み。
- 6.8 — tests use mock repository, dummy item ids, dummy URLs only。
- 6.9 — 実装ノートに `xcodebuild` 実行不可理由あり。Reviewer でも同コマンドを実行し、active developer directory が `/Library/Developer/CommandLineTools` のため失敗することを確認。
- NFR 1.1 — iOS 16+ SwiftUI の既存 app target 内変更。
- NFR 1.2 — `SafariServices` と `UIViewControllerRepresentable` wrapper を追加。
- NFR 1.3 — View は network / Keychain / Bearer token refresh details を扱わず、Repository 経由。
- NFR 1.4 — `ArticleDetailViewModel` は既存どおり `@MainActor`。
- NFR 1.5 — 追加 Swift 型名 / 識別子 / ファイル名は English。
- NFR 2.1 — 変更は ArticleDetail / AppShell の open-original flow と project registration / tests に限定。
- NFR 2.2 — `design/*`、prototype、他 Issue specs の変更なし。なお #36 の `tasks.md` / `design.md` は存在しなかった。
- NFR 2.3 — server API contract / mock JSON reliance の追加なし。
- NFR 2.4 — external browser preference / broad browser abstraction の追加なし。
- NFR 2.5 — global sync infrastructure の追加なし。既存 `ItemStateChange` boundary のみ使用。
- NFR 3.1 — real tokens / Secret / 個人情報 / 実ユーザー記事データなし。
- NFR 3.2 — token / Authorization header / full private content の log 追加なし。
- NFR 3.3 — error messages は concise Japanese user-facing messages。
- NFR 3.4 — read marking / Safari preparation に関わる repository error は user-presentable message または auth boundary に変換される。

## Findings

なし

## Summary

差分は Issue #36 の SFSafariViewController original article opener と read marking orchestration の範囲に収まっている。`tasks.md` / `design.md` は存在しなかったため task boundary annotation は照合不能だが、requirements 上の AC 未カバー、missing test、boundary 逸脱は検出しなかった。

RESULT: approve
