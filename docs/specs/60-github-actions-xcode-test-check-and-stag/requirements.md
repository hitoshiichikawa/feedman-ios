# 要件定義

## 概要

Issue #60 は Parent: #12 の子 Issue として、GitHub Actions の macOS runner 上で `xcodebuild test` を実行する CI check を整備し、idd-codex promote pipeline の ST 判定 (`ST_CHECK_RUN_NAME`) が参照できる機械的な test gate を確立する。

現状、feedman-ios には GitHub Actions workflow が存在せず、cron log に `ST_CHECK_RUN_NAME 未設定 → ST 連動停止 action=skip` の WARN が継続的に出ている。Linux 上の watcher からは Xcode test を実行できないため、macOS GitHub Actions の check 結果を ST 判定の正とする。

Issue 起票者により以下の方針が「仮案・判断を委ねたい点」として提示済みであり、Triage でこれを採用した:

- check 名は安定した `iOS Tests` に固定し、cron は `ST_CHECK_RUN_NAME="iOS Tests"` を参照する。
- GitHub Actions の macOS runner で `iPhone 16` simulator が存在しない場合は、available devices を確認して runner 標準の iPhone simulator へ寄せ、その判断を記録する。

## 要件

### Requirement 1: PR への Xcode test check

**Objective:** As a レビュワー, I want `develop` 向け PR で Xcode test が自動実行される, so that merge 前に機械的な test 結果を確認でき、手元に Xcode がない環境でもレビューできる

#### Acceptance Criteria

1. When a PR targets `develop`, GitHub Actions shall run `xcodebuild` test for scheme `Feedman` on a macOS runner.
2. When the workflow runs, the check run name shall be `iOS Tests` で安定して観測できる。
3. When the PR head に workflow 定義が含まれる, the check shall その PR 自身でも実行される。

### Requirement 2: develop 更新時の ST check

**Objective:** As a promote pipeline 運用者, I want `develop` が更新されるたびに同じ test check が走る, so that `codex-staged-for-release` Issue 群を ST check 結果と機械的に照合できる

#### Acceptance Criteria

1. When `develop` is updated by a push or merge, GitHub Actions shall run the same Xcode test check on the new head commit.
2. When the test check completes, the result shall `develop` の commit に check run `iOS Tests` として記録される。
3. While the workflow is defined, the Linux watcher shall not require local Xcode to evaluate the staged-release gate.

### Requirement 3: ST_CHECK_RUN_NAME の運用ドキュメント

**Objective:** As a idd-codex 運用者, I want README に設定すべき `ST_CHECK_RUN_NAME` 値が明記される, so that cron / launchd エントリへ正確な check 名を設定でき、WARN ログを解消できる

#### Acceptance Criteria

1. When README setup is followed, the operator shall know the exact value `ST_CHECK_RUN_NAME="iOS Tests"` to put in the feedman-ios idd-codex cron / launchd entry.
2. When the workflow trigger conditions are documented, the README shall PR 向けと `develop` push 向けの両方の実行条件を説明する。
3. When GitHub Actions is unavailable or the simulator name changes, the README shall failure mode と手動検証コマンドを案内する。

### Requirement 4: Simulator 選定の記録

**Objective:** As a 後続の開発者, I want CI で使う simulator 名と選定理由が記録される, so that runner image 更新で simulator が変わった際に判断を再現できる

#### Acceptance Criteria

1. If the GitHub Actions macOS runner image does not provide an `iPhone 16` simulator, the workflow shall runner で利用可能な標準 iPhone simulator を使用する。
2. When the simulator used by CI differs from the README's local verification command, the decision shall impl-notes と README に記録される。
3. The workflow shall simulator 名をハードコードする場合でも、判断根拠を docs/specs 配下に残す。

## 非機能要件

### NFR 1: Scope control

1. The implementation shall App Store signing / archive / upload automation を含めない。
2. The implementation shall Fastlane を導入しない。
3. The implementation shall UI snapshot test / TestFlight 配布を含めない。
4. The implementation shall promote pipeline 本体 (idd-codex 側) を修正しない。

### NFR 2: Security / Secrets

1. The workflow shall Secrets や signing certificate を参照しない。
2. The workflow shall 実 token、個人情報を含めない。

### NFR 3: Compatibility

1. The workflow shall iOS 16+ / SwiftUI / XCTest の既存方針に従い、`Feedman.xcodeproj` の `Feedman` scheme を対象とする。
2. The check shall public repository の無償 GitHub Actions macOS runner で実行できる。

## スコープ外

- App Store signing / archive / upload automation
- Fastlane 導入
- UI snapshot tests
- TestFlight 配布
- promote pipeline 本体の修正 (idd-codex 側の責務)
- branch protection 設定の変更 (運用者の GitHub 設定操作)

## 実装境界

- 追加対象: `.github/workflows/` 配下の workflow 1 本、README.md の CI / 運用ドキュメント節。
- 必要に応じて `design/ZERO-TO-IDD-CODEX-NOTES.md` へ参照を追記してよいが、必須ではない。
- Swift コード、Xcode project 設定、テストコードは変更しない。

## 確認事項

- GitHub Actions macOS runner image の Xcode version と simulator 一覧は実行時にしか確定しないため、workflow 内で available destinations を確認できる手段 (ログ出力) を残し、実 run の結果を impl-notes に記録する。
- check run 名は workflow の job name が GitHub check run name として観測されることを前提に、job name を `iOS Tests` に固定する。
