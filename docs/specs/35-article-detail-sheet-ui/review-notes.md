# Review Notes

<!-- idd-codex:review round=3 model=gpt-5.5 timestamp=2026-06-16T00:24:41Z -->

## Reviewed Scope

- Branch: codex/issue-35-impl-article-detail-sheet-ui
- HEAD commit: aa63aa3d2dc8e81029da326f49d7db5c656afc7d
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `ArticleDetailSheet.swift:65` で `.presentationDetents([.medium, .large])` を指定。
- 1.2 — `ArticleDetailSheet.swift:65` と `impl-notes.md:60` で medium detent を preview 表示として扱う構造を確認。
- 1.3 — `ArticleDetailSheet.swift:51` / `SharedPrimitives.swift:507` で large detent でも同一 ScrollView content を表示し、別 full-screen route を追加していない。
- 1.4 — `ArticleDetailSheet.swift:10` で item ごとの `ArticleDetailSheetInput` から `@StateObject` を生成し、dismiss は parent callback / sheet lifecycle に委譲。
- 1.5 — `ArticleDetailSheet.swift:33` で #27 の `FeedmanSheetShell` を利用し、custom gesture engine は追加していない。
- 1.6 — `ArticleDetailSheet.swift:174` / `SharedPrimitives.swift:535` / `impl-notes.md:62` で title wrap、dismiss button、narrow width / Dynamic Type 相当の確認 notes を確認。
- 2.1 — `ArticleDetailViewModel.swift:323` で `ItemRepository.itemDetail(id:accessToken:)` を呼び出す。
- 2.2 — `ArticleDetailSheet.swift:96` / `ArticleDetailSheet.swift:102` で `FeedmanLoadingView` を利用。
- 2.3 — `ArticleDetailPresentation.init(detail:)` が `ItemDetail` から content / read / starred / hatebu / author / link を構成。
- 2.4 — `ArticleDetailSheet.swift:98` で summary preview を表示し、成功後は `ArticleDetailSheet.swift:104` の loaded content に置換。
- 2.5 — `ArticleDetailSheet.swift:108` で `FeedmanRecoverableErrorView` を利用。
- 2.6 — `ArticleDetailSheet.swift:58` / `ArticleDetailViewModel.swift:279` と `testDetailFailureShowsRecoverableStateAndRetryUsesSameItem` で retry を確認。
- 2.7 — `ArticleDetailViewModel.swift:240` が repository に依存し、HTTP request / Keychain / URLSession 直接依存はない。
- 3.1 — `ArticleDetailSheet.swift:169` で `ArticleSourceRow` を利用し、`ArticleDetailViewModel.swift:97` で feed title / favicon を渡す。
- 3.2 — `ArticleSourceRow` は `FeedmanFaviconView` 経由で favicon を扱い、`ArticleDetailSheet` は `AsyncImage(url:)` を直接使っていない。
- 3.3 — `ArticleDetailSheet.swift:174` の `fixedSize(horizontal:false, vertical:true)` と `impl-notes.md:62` で長い title の wrap を確認。
- 3.4 — `ArticleDetailViewModel.swift:125` で RFC3339 String を表示層用 text に整形し、`ArticleSourceRow` に渡す。
- 3.5 — `ArticleDetailViewModel.swift:136` と `ArticleDetailSheet.swift:225` で estimated state を表示。
- 3.6 — `ArticleDetailViewModel.swift:110` / `ArticleDetailSheet.swift:211` で author を secondary metadata として表示。
- 3.7 — `ArticleDetailViewModel.swift:114` / `ArticleMetadataControls.swift:169` で hatebu unavailable と zero を区別。
- 3.8 — `ArticleDetailSheet.swift:262` / `ArticleMetadataControls.swift:162` で shared star control と accessibility label/value を利用。
- 4.1 — `SharedPrimitives.swift:507` の ScrollView と `impl-notes.md:60`-`64` の manual verification notes で長文 preview scroll / 非重なりを確認。
- 4.2 — `ArticleDetailContentPreview` が HTML tag strip / entity decode の readable text を生成し、`testContentPreviewUsesReadableHTMLText` で検証。
- 4.3 — `ArticleDetailViewModel.swift:181`-`199` が raw tag を primary 表示にしない fallback を持ち、同テストで raw tag 非表示を確認。
- 4.4 — `ArticleDetailViewModel.swift:162`-`174` と `testContentPreviewFallsBackToSummaryAndNeutralEmptyText` で summary / neutral empty fallback を確認。
- 4.5 — `SharedPrimitives.swift:515`-`524` で footer は ScrollView の sibling、`SharedPrimitives.swift:531` で bottom inset を確保。
- 4.6 — `ArticleDetailSheet.swift:65` と `impl-notes.md:60` で medium detent は scroll または large drag により継続閲覧可能。
- 4.7 — `ArticleDetailSheet.swift:191` の content text は line limit なし、`impl-notes.md:61` で large detent の読了可能構造を確認。
- 5.1 — `ArticleDetailViewModel.swift:269`-`276` で open 時に read marking を要求。
- 5.2 — `ArticleDetailViewModel.swift:337`-`340` と `testOpenFetchesDetailAndMarksReadWithPartialRequest` で `isRead: true, isStarred: nil` を確認。
- 5.3 — `ArticleDetailViewModel.swift:337` は unread 化を行わず、idempotent な `isRead: true` のみを送る。
- 5.4 — `ArticleDetailViewModel.swift:347` / `ArticleDetailSheet.swift:88` と `testReadMarkingFailureDoesNotBlockLoadedDetail` で non-blocking message を確認。
- 5.5 — `ArticleDetailViewModel.swift:352`-`355` で sheet-local presentation のみ更新。
- 5.6 — 差分に list / starred / search の global sync や rollback orchestration はない。
- 5.7 — `ArticleDetailViewModel.swift:275` で detail fetch 前に read marking を実行。
- 6.1 — `ArticleDetailSheet.swift:241`-`269` で fixed footer に「元記事を開く」と star affordance を配置。
- 6.2 — `ArticleDetailViewModel.swift:298`-`301` と `testStarToggleSendsPartialStarRequestAndUpdatesSheetLocalState` で star-only partial update を確認。
- 6.3 — `ArticleDetailViewModel.swift:283`-`294` と `ArticleDetailSheet.swift:262`-`268` で in-flight 中の重複操作を防止。
- 6.4 — `ArticleDetailViewModel.swift:303` と `testStarToggleSendsPartialStarRequestAndUpdatesSheetLocalState` で sheet-local star state 更新を確認。
- 6.5 — `ArticleDetailViewModel.swift:305`-`307` と `testStarFailureKeepsDeterministicFinalStateAndSurfacesMessage` で失敗時 message と deterministic state を確認。
- 6.6 — `ArticleDetailSheet.swift:250`-`252` は caller callback のみで、SFSafariViewController を実装していない。
- 6.7 — `ArticleDetailSheet.swift:15` / `ArticleDetailSheet.swift:250` で caller-provided callback に留めている。
- 6.8 — `ArticleDetailViewModel.swift:139`-`148` / `ArticleDetailSheet.swift:258` と `testPresentationDisablesInvalidOriginalLink` で invalid link disable を確認。
- 7.1 — dismiss / open-original / content preview は `ArticleDetailSheet.swift:36` / `ArticleDetailSheet.swift:259` / `ArticleDetailSheet.swift:196`、loading / retry は shared primitives で label を持つ。
- 7.2 — `ArticleMetadataControls.swift:162`-`165` で star selected / unselected state を accessibility value / selected trait として公開。
- 7.3 — `ArticleMetadataControls.swift:151` と `ArticleDetailSheet.swift:255` で icon shape / label を使い、色だけに依存しない。
- 7.4 — `ArticleDetailSheet.swift` は `FeedmanTheme` と existing DesignSystem controls を利用し、feature-local raw palette は追加していない。
- 7.5 — `ArticleDetailSheet.swift` と `SharedPrimitives.swift` は semantic token を利用しており、light/dark 固有の hardcoded foreground/background を追加していない。
- 7.6 — `ArticleMetadataControls.swift:155`-`156` と `SharedPrimitives.swift:650` で 44pt 以上の touch target を確認。
- 7.7 — 差分に keyword notification UI / drawer route はない。
- 8.1 — `testOpenFetchesDetailAndMarksReadWithPartialRequest` で detail request を検証。
- 8.2 — 同 test で read marking の `isRead == true` / `isStarred == nil` を検証。
- 8.3 — 同 test で source / title / author / preview / star state を検証。
- 8.4 — `testDetailFailureShowsRecoverableStateAndRetryUsesSameItem` で error / retry を検証。
- 8.5 — `testStarToggleSendsPartialStarRequestAndUpdatesSheetLocalState` で star partial update / local transition を検証。
- 8.6 — `testStarFailureKeepsDeterministicFinalStateAndSurfacesMessage` で star failure surface / final state を検証。
- 8.7 — `testContentPreviewFallsBackToSummaryAndNeutralEmptyText` / `testContentPreviewKeepsLongContentAsReadableText` と `impl-notes.md:57`-`65` で nil / empty / long / non-overlap を確認。
- 8.8 — `impl-notes.md:75`-`77` と reviewer 再実行で、Xcode 本体不在により xcodebuild 実行不可であることを確認。

## Findings

なし

## Summary

差分は取得済みで、`develop..HEAD` は ArticleDetail の View / ViewModel / ViewModel tests と、footer padding 用の shared primitive 小変更が中心だった。`tasks.md` と `design.md` は存在しなかったため、`requirements.md`、`impl-notes.md`、実装差分、テスト差分を突き合わせて判定した。

Reviewer 側でも `plutil -lint Feedman.xcodeproj/project.pbxproj` と `git diff --check develop..HEAD` は成功。`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は active developer directory が `/Library/Developer/CommandLineTools` のため実行不可だった。

RESULT: approve
