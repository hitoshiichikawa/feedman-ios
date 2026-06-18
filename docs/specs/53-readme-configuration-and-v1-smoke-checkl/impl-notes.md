# Issue #53 実装メモ

## 実装概要

- `README.md` に macOS/Xcode 前提の開発手順、canonical test command、`iPhone 16` simulator が無い場合の確認コマンドを整理した。
- `README.md` に API base URL の現在の設定境界、native auth callback、mock / preview data の位置づけを追加した。
- `README.md` に v1 smoke test checklist を追加し、ログイン、横断タイムライン、記事詳細、Safari、スター、フィード別 filter、フィード登録、検索、ログアウトを確認対象にした。
- Debug / Release / Staging / Local の正式な API base URL、production endpoint、signing、OAuth client ID などの未決値は作らず、未決として明記した。

## 変更ファイル

- `README.md`
- `docs/specs/53-readme-configuration-and-v1-smoke-checkl/requirements.md`（PM 作成済み成果物を保持）
- `docs/specs/53-readme-configuration-and-v1-smoke-checkl/impl-notes.md`

## 検証

- `README.md` の見出し、箇条書き、コードブロックを目視確認した。
- canonical test command が `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` と一致していることを確認した。
- `README.md` が `iOS Tests` check run 名を維持していることを確認した。
- ドキュメント変更のみのため、Xcode test は実行していない。Swift source、Xcode project、Info.plist、GitHub Actions workflow は変更していない。

## 確認事項

- なし
