# Review Notes

<!-- idd-claude:review round=1 model=claude-fable-5 timestamp=2026-06-11T20:22:12Z -->

## Reviewed Scope

- Branch: codex/issue-60-impl-github-actions-xcode-test-check-and-stag
- HEAD commit: 2d2dadd8d023d8bfe842bf8dbfebc851c5ae2caf
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `.github/workflows/ios-tests.yml` の `on.pull_request.branches: [develop]` で `develop` 向け PR に macos-15 runner の `xcodebuild test` が走る。
- 1.2 — job name が `iOS Tests` に固定され、check run 名として観測される。job 定義に変更禁止のコメントを付記済み。
- 1.3 — pull_request trigger は PR head の workflow 定義で実行されるため、workflow を追加する本 PR 自身でも check が走る。実 run の結果は PR 上で確認する。
- 2.1 — `on.push.branches: [develop]` で merge を含む `develop` 更新時に同一 check が走る。
- 2.2 — push trigger の check run は pushed commit (develop HEAD) に紐づく。
- 2.3 — watcher は GitHub API 経由で check run を照合するため、Linux 側に Xcode を要求しない。
- 3.1 — README の `## CI` 節に `ST_CHECK_RUN_NAME="iOS Tests"` を明記し、idd-codex 節の cron 例・launchd EnvironmentVariables 一覧にも追記。
- 3.2 — README に PR 向け / `develop` push 向けの両実行条件を記載。
- 3.3 — README に GitHub Actions 不可時の手動検証コマンドと simulator 読み替え手順を記載。
- 4.1 — `Resolve simulator destination` step が `iPhone 16` を `grep -x` (完全一致) で優先し、不在時は available な最初の iPhone simulator へ寄せる。`iPhone 16e` の誤選択なし (ローカルで fallback 動作を検証済み)。
- 4.2 — simulator 選定の判断を impl-notes と README に記録。
- 4.3 — 判断根拠は `docs/specs/60-github-actions-xcode-test-check-and-stag/` 配下に残置。
- NFR 1.1〜1.4 — signing / Fastlane / snapshot / TestFlight / promote pipeline 本体の変更は含まれない。
- NFR 2.1〜2.2 — workflow は Secrets を参照せず、`permissions: contents: read` の最小権限。
- NFR 3.1〜3.2 — `Feedman.xcodeproj` の `Feedman` scheme を対象とし、public repo の無償 macOS runner で実行可能。

## Findings

- workflow YAML の靜的検証はローカルに actionlint / PyYAML が無いため未実施。本 PR の実 run を green 確認してから merge することを merge 条件とする。

## Summary

`tasks.md` と `design.md` は本 spec に存在しない (design-less 1 PR 直行ルート)。boundary は `requirements.md` の実装境界と develop..HEAD 差分で確認した。Swift コード / Xcode project への変更はなく、スコープ逸脱なし。

RESULT: approve (条件: PR 上の `iOS Tests` check run が green であること)
