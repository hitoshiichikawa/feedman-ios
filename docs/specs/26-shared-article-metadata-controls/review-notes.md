# Review Notes

<!-- idd-codex:review round=2 model=gpt-5 timestamp=2026-06-12T00:00:00+09:00 -->

## Reviewed Scope

- Branch: `codex/issue-26-impl-shared-article-metadata-controls`
- HEAD commit: `756c8ccc18d536b65cf8c96374da16dbd2043df4`
- Compared to: `develop..HEAD`
- Review round: 2 / 2
- Previous result: `RESULT: reject`

## Diff Summary

`git diff --stat develop..HEAD` は空ではなく、以下の差分を確認した。

- `Feedman/DesignSystem/ArticleMetadataControls.swift`
- `FeedmanTests/ArticleMetadataControlsTests.swift`
- `Feedman.xcodeproj/project.pbxproj`
- `docs/specs/26-shared-article-metadata-controls/requirements.md`
- `docs/specs/26-shared-article-metadata-controls/impl-notes.md`

`git log --oneline develop..HEAD`:

- `756c8cc test: cover article control card interactions`
- `26bb488 feat: add shared article metadata controls`

指定必読ファイルのうち `tasks.md` と `design.md` は存在しなかったため、tasks の boundary annotation と design.md 固有の追加要件は照合できなかった。

## Verified Requirements

- Requirement 1: `ArticleStarControl` / `ArticleStarControlDescriptor` は starred / unstarred の icon、theme color role、accessibility label / value / selected trait、disabled guard、44pt touch target、caller-provided action を満たしている。
- Requirement 1.6: round 1 指摘に対し、`testStarActivationCallsOnlyCallerProvidedAction` が tappable article card 相当の親 `onTapGesture` と `ArticleStarControl` を同じ SwiftUI harness に結線し、star action のみが呼ばれることを検証している。
- Requirement 2: `ArticleHatebuCountState` / `ArticleHatebuCountControl` は available / unavailable を明示的に分け、`-` placeholder、zero との差別化、100 件以上の accent state、compact / standard / timeline size option、安定した minWidth / minHeight を提供している。
- Requirement 3: `ArticleSourceRow` は `FeedmanFaviconView` を利用し、metadata `nil` で非表示、feed title の単一行 truncation、relative date の併置、favicon size の安定化を提供している。`data:` URL は `AsyncImage(url:)` へ直接渡していない。
- Requirement 4: `ArticleOpenLinkControl` / `ArticleOpenLinkControlDescriptor` は external-link icon、accessibility label、caller-provided action、disabled / hidden unavailable state、Safari presentation / read mutation 非依存、安定 touch target を満たしている。
- Requirement 4.4: round 1 指摘に対し、`testOpenLinkDescriptorCallsOnlyCallerProvidedActionWithValue` が tappable article card 相当の親 `onTapGesture` と `ArticleOpenLinkControl` を同じ SwiftUI harness に結線し、open-link action のみが呼ばれることを検証している。
- Requirement 5: source row、relative date、title / summary 側と組み合わせる metadata controls、hatebu、star、open-link を Feature 側から compose できる API になっており、read-state mutation、network、Keychain、Safari 依存は共有 controls に入っていない。
- NFR 1 / 2 / 3: DesignSystem token 利用、favicon component 利用、iOS 16+ SwiftUI、stable dimensions、icon-only controls の VoiceOver label、hatebu unavailable の非 zero 表現、caller-provided action 境界を確認した。

## Findings

今回のレビュー観点である AC 未カバー、missing test、boundary 逸脱に該当する reject 指摘は確認しなかった。

## Verification

- `plutil -lint Feedman.xcodeproj/project.pbxproj`: 成功。
- `xcrun swiftc -parse Feedman/DesignSystem/ArticleMetadataControls.swift Feedman/DesignSystem/FeedmanTheme.swift Feedman/DesignSystem/FeedmanFaviconView.swift`: 成功。
- `xcrun swiftc -parse FeedmanTests/ArticleMetadataControlsTests.swift`: 成功。
- `git diff --check develop..HEAD`: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`: 未実行。active developer directory が `/Library/Developer/CommandLineTools` で、`tool 'xcodebuild' requires Xcode` により終了した。Xcode が選択された macOS 環境で再実行が必要。

## Summary

round 1 の reject 理由だった「tappable article card 内で star / open-link を起動したとき、親 card open action が呼ばれないことのテスト不足」は `756c8cc` で解消されている。差分取得は成功し、対象差分は空ではない。`tasks.md` / `design.md` 不在と `xcodebuild test` 未実行は残るが、今回指定された reject 対象カテゴリでは追加指摘なしと判断する。

RESULT: approve
