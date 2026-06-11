# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-11T21:15:30Z -->

## Reviewed Scope

- Branch: codex/issue-27-impl-reusable-loading-empty-error-toast-and-s
- HEAD commit: e0f1066780490f0b4f6a730786c2baeffe3a5364
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `Feedman/DesignSystem/SharedPrimitives.swift:3` の `FeedmanLoadingView` が activity indicator と optional message を提供。
- 1.2 — `Feedman/DesignSystem/SharedPrimitives.swift:42` の `FeedmanCompactLoadingRow` が list bottom 用の compact loading row を提供。
- 1.3 — `Feedman/DesignSystem/SharedPrimitives.swift:7` と `Feedman/DesignSystem/SharedPrimitives.swift:46` で message 省略時も default accessibility label を保持。
- 1.4 — `Feedman/DesignSystem/SharedPrimitives.swift:19`、`Feedman/DesignSystem/SharedPrimitives.swift:30`、`Feedman/DesignSystem/SharedPrimitives.swift:58`、`Feedman/DesignSystem/SharedPrimitives.swift:68` で spinner と container の stable dimension を設定。
- 1.5 — `Feedman/DesignSystem/SharedPrimitives.swift:18`、`Feedman/DesignSystem/SharedPrimitives.swift:24`、`Feedman/DesignSystem/SharedPrimitives.swift:31`、`Feedman/DesignSystem/SharedPrimitives.swift:34` で `FeedmanTheme` token を使用。
- 2.1 — `Feedman/DesignSystem/SharedPrimitives.swift:75` の `FeedmanEmptyStateView` が icon/title/optional subtitle を表示。
- 2.2 — `Feedman/DesignSystem/SharedPrimitives.swift:107` と `Feedman/DesignSystem/SharedPrimitives.swift:115` で long text / Dynamic Type 向けに wrap を許容。
- 2.3 — `Feedman/DesignSystem/SharedPrimitives.swift:119` で optional primary action を共通 layout と button style で表示。
- 2.4 — `Feedman/DesignSystem/SharedPrimitives.swift:133` の action なし initializer と `Feedman/DesignSystem/SharedPrimitives.swift:119` の条件分岐で action 未指定時の control area を省略。
- 2.5 — `Feedman/DesignSystem/SharedPrimitives.swift:81` が SF Symbols の `systemImage` を caller から受け取る。
- 2.6 — `Feedman/DesignSystem/SharedPrimitives.swift:97`、`Feedman/DesignSystem/SharedPrimitives.swift:99`、`Feedman/DesignSystem/SharedPrimitives.swift:106`、`Feedman/DesignSystem/SharedPrimitives.swift:113`、`Feedman/DesignSystem/SharedPrimitives.swift:127` で theme token を使用。
- 3.1 — `Feedman/DesignSystem/SharedPrimitives.swift:146` の `FeedmanRecoverableErrorView` が retry action builder を提供。
- 3.2 — `Feedman/DesignSystem/SharedPrimitives.swift:174` で title/message の階層表示を提供。
- 3.3 — `Feedman/DesignSystem/SharedPrimitives.swift:217` の retry なし initializer と `Feedman/DesignSystem/SharedPrimitives.swift:190` の条件分岐で non-retry 表示を提供。
- 3.4 — `Feedman/DesignSystem/SharedPrimitives.swift:155`、`Feedman/DesignSystem/SharedPrimitives.swift:168`、`Feedman/DesignSystem/SharedPrimitives.swift:170` で `danger` emphasis を選択可能。
- 3.5 — `FeedmanRecoverableErrorView` は title/message/action の UI primitive のみで、`FeedmanAPIError` や endpoint code 参照なし。
- 3.6 — `Feedman/DesignSystem/SharedPrimitives.swift:193` と `Feedman/DesignSystem/SharedPrimitives.swift:206` で retry control と error content の accessibility label を提供。
- 4.1 — `Feedman/DesignSystem/SharedPrimitives.swift:269` の `FeedmanToastCenter` が show/dismiss と duration-based dismiss を提供。
- 4.2 — `Feedman/DesignSystem/SharedPrimitives.swift:317` の `FeedmanToastView` と `Feedman/DesignSystem/SharedPrimitives.swift:376` の `allowsHitTesting(false)` が optional status icon と non-blocking overlay を提供。
- 4.3 — `Feedman/DesignSystem/SharedPrimitives.swift:396` の `FeedmanBannerView` が message と optional action affordance を提供。
- 4.4 — `Feedman/DesignSystem/SharedPrimitives.swift:282` が replacement policy を実装し、`FeedmanTests/FeedmanTests.swift:80` が replacement を検証。
- 4.5 — `Feedman/DesignSystem/SharedPrimitives.swift:332` と `Feedman/DesignSystem/SharedPrimitives.swift:423` で long text の multi-line 表示を許容。
- 4.6 — `Feedman/DesignSystem/SharedPrimitives.swift:331`、`Feedman/DesignSystem/SharedPrimitives.swift:339`、`Feedman/DesignSystem/SharedPrimitives.swift:342`、`Feedman/DesignSystem/SharedPrimitives.swift:434`、`Feedman/DesignSystem/SharedPrimitives.swift:437` で theme token を使用。
- 4.7 — toast/banner は message/style/action の表示だけで、endpoint 固有 retry/resume/registration/logout 処理なし。
- 5.1 — `Feedman/DesignSystem/SharedPrimitives.swift:479` の `FeedmanSheetShell` が title/subtitle/dismiss header を提供。
- 5.2 — `Feedman/DesignSystem/SharedPrimitives.swift:588` と `Feedman/DesignSystem/SharedPrimitives.swift:607` の `feedmanSheet` が default detents `[.medium, .large]` を提供。
- 5.3 — `Feedman/DesignSystem/SharedPrimitives.swift:507` で content を scrollable にし、header/action area を scroll 外に保持。
- 5.4 — `Feedman/DesignSystem/SharedPrimitives.swift:513` で primary action bar を scroll content から分離し、border/surface token を使用。
- 5.5 — `Feedman/DesignSystem/SharedPrimitives.swift:571` の action なし initializer と `Feedman/DesignSystem/SharedPrimitives.swift:513` の条件分岐で empty action bar を省略。
- 5.6 — `Feedman/DesignSystem/SharedPrimitives.swift:536`、`Feedman/DesignSystem/SharedPrimitives.swift:557`、`Feedman/DesignSystem/SharedPrimitives.swift:567` で sheet title と dismiss control の accessibility を提供。
- 5.7 — `Feedman/DesignSystem/SharedPrimitives.swift:596` と `Feedman/DesignSystem/SharedPrimitives.swift:615` で native SwiftUI `.sheet` を使用。
- 6.1 — reusable components は `Feedman/DesignSystem/SharedPrimitives.swift` に集約され、差分上の feature 本実装変更なし。
- 6.2 — `Feedman/DesignSystem/SharedPrimitives.swift:658`、`:686`、`:712`、`:730` に loading/empty/error/toast/banner/sheet shell の light/dark representative preview を確認。round 1 の sheet shell dark mode 不足は `Sheet Shell Dark` で解消済み。
- 6.3 — `FeedmanTests/FeedmanTests.swift:80` で deterministic toast replacement、`:92` で manual dismiss を unit test。
- 6.4 — `docs/specs/27-reusable-loading-empty-error-toast-and-s/impl-notes.md:25` 以降に UI-only layout の手動確認ポイントを記載。
- 6.5 — `docs/specs/27-reusable-loading-empty-error-toast-and-s/impl-notes.md:23` と `:43` に Xcode.app 不在による `xcodebuild` 未実行制約を記載。Reviewer 側でも同じ `xcode-select` エラーを確認。
- NFR 1.1 — `Feedman.xcodeproj/project.pbxproj` に app target source として追加され、SwiftUI/iOS 16+ API 範囲で実装。
- NFR 1.2 — primitive は `URLSession`、Keychain、Repository、APIClient に依存していない。
- NFR 1.3 — Swift 型名、識別子、ファイル名は英語。
- NFR 1.4 — text は `fixedSize(horizontal: false, vertical: true)` と multi-line alignment を使い、固定 text clipping を避ける実装。
- NFR 2.1 — loading/error/retry/dismiss/toast/banner の accessibility label を確認。empty icon は装飾扱いで hidden。
- NFR 2.2 — error/warning/success は icon と text を併用し、色だけに依存していない。
- NFR 2.3 — primary/secondary action styles と dismiss button は 44pt/36pt 相当の touch target を確保。
- NFR 3.1 — shared UI primitive に限定され、feature-specific business logic は追加なし。
- NFR 3.2 — reviewer は `docs/specs/*` を書き換えていない。差分上は requirements/impl-notes が追加されているが、実装差分に確定済み仕様の書き換えは確認できない。
- NFR 3.3 — shared UI requirements に API contract や mock data shape を導入していない。
- NFR 3.4 — keyword notification UI や drawer/sheet 導線の追加なし。

## Findings

なし

## Summary

差分は空ではなく、round 1 の AC 6.2 指摘は `Sheet Shell Dark` preview 追加で解消済みです。`tasks.md` と `design.md` は指定 spec ディレクトリに存在しないため、boundary は `requirements.md` の実装境界と差分パスで代替確認しました。`xcodebuild` は Xcode.app 不在で実行不能でした。

RESULT: approve
