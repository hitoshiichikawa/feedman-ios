# Issue #25 Favicon data URL and letter avatar view 要件定義

## 背景

Epic #4 の UI 基盤を後続 feature 実装で再利用できるようにするため、Feedman の favicon 表示を SwiftUI の DesignSystem component として定義する。
`design/SPEC-iOS.md` では、`feed_favicon_url` / `favicon_url` は `data:<mime>;base64,...` 形式の data URL または `null` であり、`AsyncImage(url:)` ではなく専用 view で `Data(base64:)` decode して `UIImage` 化する方針が定義されている。
decode できない場合や値がない場合は、プロトタイプ `design/mobile/fm-ui.jsx` の `FMFavicon` と同様に、安定した色付きレターアバターへフォールバックする。

Issue コメントでは依存 `Depends on: #24` が PR #64 として develop へ merge 済みであることが人間により確認済みで、編集見込み path は `Feedman/DesignSystem/` と `FeedmanTests/` に限定されている。

## スコープ

- `Feedman/DesignSystem` に favicon data URL 表示とレターアバター fallback を担う SwiftUI component を追加する。
- `feed_favicon_url` / `favicon_url` に入る `data:<mime>;base64,...` 形式の文字列を扱う。
- `nil`、空文字、不正な data URL、不正な base64、画像化できない data はレターアバターにフォールバックする。
- レターアバターの文字は feed title など呼び出し側が渡す表示名から決定できるようにする。
- レターアバターの背景色は同じ入力に対して安定して決まるようにする。
- list 内で使っても寸法が揺れないよう、size と corner radius を指定可能にする。
- data URL decode、fallback 文字、安定色決定などの非 UI ロジックは `FeedmanTests` で単体テストできる形にする。

## スコープ外

- Remote image URL の取得、download、cache、retry。
- Nuke、Kingfisher など remote image caching library の導入。
- OGP thumbnail の表示、取得、placeholder 実装。
- Feature screen 全体への広範な組み込みや既存画面のレイアウト調整。
- API model の契約変更、repository、network、auth の変更。
- favicon の永続 cache、disk cache、prefetch。
- feed 登録時の favicon 取得ロジックやサーバー実装。
- `docs/specs/*` の既存確定仕様の変更。

## 機能要件

- When favicon source is a valid base64 data URL, the favicon component shall decode the payload and render it as an image.
- When favicon source is `nil`, the favicon component shall render a colored letter avatar.
- When favicon source is an empty string, the favicon component shall render a colored letter avatar.
- When favicon source is not a `data:` URL, the favicon component shall render a colored letter avatar.
- When favicon source is a `data:` URL without a valid `;base64,` payload, the favicon component shall render a colored letter avatar.
- When favicon source has invalid base64 data, the favicon component shall render a colored letter avatar.
- When decoded data cannot be converted to a `UIImage`, the favicon component shall render a colored letter avatar.
- When a display name is provided for fallback, the letter avatar shall use the first user-visible character of the trimmed display name.
- If the display name is empty or missing, the letter avatar shall use `?` as the fallback letter.
- When the same display name is used repeatedly, the letter avatar shall use the same background color.
- When different display names are used, the letter avatar should distribute background colors across a small predefined palette without requiring randomness.
- When size is specified, the component shall keep both width and height equal to that size.
- When corner radius is specified, the component shall apply that radius to both image and avatar states.
- While used in SwiftUI lists, the component shall avoid layout shifts between decoded image, loading-free fallback, and invalid-source fallback states.
- When the component renders fallback text, it shall use readable foreground contrast over the selected avatar background.
- When data URL decode is performed, the implementation shall not pass `data:` URLs to `AsyncImage(url:)`.

## 非機能要件

- 実装は iOS 16+ の SwiftUI で利用できること。
- 共有 UI component として `Feedman/DesignSystem` から利用できる public/internal API にすること。
- Swift の型名、識別子、ファイル名は英語にすること。
- data URL parse と base64 decode は単体テストしやすい小さな責務へ分離すること。
- decode 失敗は通常の fallback 条件として扱い、UI を crash させないこと。
- data URL の mime type は画像表示の補助情報として扱い、API 契約外の remote URL 処理へ拡張しないこと。
- Avatar palette は #24 の Feedman theme token と併用しやすい固定値または DesignSystem 内の定義として管理すること。
- 実装は Issue #25 の責務に閉じ、`Feedman/DesignSystem` と `FeedmanTests` を中心にすること。
- docs 配下の記述は日本語にし、EARS keyword は英語固定にすること。

## 受入基準

- When `faviconURL` is `data:image/png;base64,...` and the payload is a valid image, the component shall render the decoded image.
- When `faviconURL` is `nil`, the component shall render a stable colored letter avatar.
- When `faviconURL` is malformed, non-base64, or not image data, the component shall render a stable colored letter avatar.
- When the fallback display name is `Feedman Blog`, the avatar shall render `F`.
- When the fallback display name contains leading or trailing whitespace, the avatar shall derive the letter from the trimmed value.
- When the fallback display name is missing or blank, the avatar shall render `?`.
- When the same display name is evaluated in multiple test runs, the chosen avatar color shall be deterministic.
- When the component is created with a fixed size, image and avatar states shall expose stable square dimensions for list usage.
- The implementation shall include XCTest coverage for valid data URL decode, invalid data URL fallback, fallback letter derivation, and deterministic avatar color selection.
- The implementation shall not introduce remote image caching libraries or OGP thumbnail behavior.

## 確認事項

- `design/SERVER.md` には favicon の追加契約はなく、favicon 表示の API 契約は `design/SPEC-iOS.md` §4.3 と §4.4 を正本とする。
- `FMFavicon` prototype は letter/color を mock data から受け取るが、iOS の API 契約には `favicon_letter` や `favicon_color` は存在しないため、iOS 側で表示名から文字と安定色を決定する。
- Feature screen への実適用範囲は後続 Issue の責務とし、本 Issue では DesignSystem component と単体テスト可能な基盤を完成条件とする。
