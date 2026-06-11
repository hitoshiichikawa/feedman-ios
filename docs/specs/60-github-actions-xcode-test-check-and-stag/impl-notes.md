# 実装メモ

## 実装内容

- `.github/workflows/ios-tests.yml` を追加した。
  - trigger は `pull_request` (base: `develop`) と `push` (branch: `develop`) の 2 系統。
  - job name を `iOS Tests` に固定し、GitHub check run 名として観測できるようにした。idd-codex promote pipeline の `ST_CHECK_RUN_NAME="iOS Tests"` はこの名前を参照する。
  - runner は `macos-15`。`permissions: contents: read` の最小権限とし、Secrets / signing certificate は参照しない。
  - `Resolve simulator destination` step で `xcrun simctl list devices available` から `iPhone 16` を優先選択し、存在しない場合は利用可能な最初の iPhone simulator へ寄せる。選定結果は CI ログに出力される。
  - `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination "platform=iOS Simulator,name=<resolved>" test` を実行する。
  - `concurrency` で同一 ref の重複 run を抑制し、PR では古い run を cancel する。`timeout-minutes: 30`。
- `README.md` に `## CI` 節を追加し、check run 名 `iOS Tests`、実行条件 (PR / `develop` push)、`ST_CHECK_RUN_NAME="iOS Tests"` の設定値、GitHub Actions が使えない場合の手動検証コマンドを記載した。
- `README.md` の idd-codex 節にある Linux cron 例と macOS launchd の EnvironmentVariables 一覧へ `ST_CHECK_RUN_NAME` を追記した。

## Simulator 選定の判断 (Req 4)

- README / AGENTS.md の検証コマンドは `iPhone 16` を指定しているため、CI でも `iPhone 16` を第一候補とする。
- GitHub Actions runner image の simulator 構成は image 更新で変わるため、`iPhone 16` 不在時は available な最初の iPhone simulator へ自動で寄せる方式にした (ハードコードで固定すると image 更新のたびに workflow が壊れるため)。
- 名前の完全一致 (`grep -x`) で照合しており、`iPhone 16e` などの別機種を誤選択しない。

## テスト

- ローカル macOS (Xcode 26.0, iPhone 16 simulator なし) で simulator 解決スクリプトを単体実行し、`iPhone 17 Pro` (最初の available iPhone) へフォールバックすることを確認した。
- workflow 全体の検証は本 PR 自身の `iOS Tests` check run で行う (pull_request trigger は PR head の workflow 定義で実行されるため、本 PR で実機検証できる)。実 run の結果は PR 上で確認する。

## 検証

- 実行: simulator 解決スクリプトのローカル実行
  - 結果: 成功。`iPhone 16` 不在環境で `iPhone 17 Pro` を選択。
- 実行: 本 PR の `iOS Tests` check run (GitHub Actions / macos-15)
  - 結果: PR 作成後に確認し、レビューコメントへ記録する。

## 確認事項

- `macos-15` runner image の default Xcode と simulator 一覧は image 更新で変わる。`iPhone 16` が消えた場合もフォールバックで動作するが、README の手動検証コマンドの simulator 名は据え置きのため、大きく乖離したら README 側を更新する。
- branch protection で `iOS Tests` を required check にするかは運用者の判断とし、本 Issue では設定しない (スコープ外)。
