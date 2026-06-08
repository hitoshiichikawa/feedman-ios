# ゼロからスケルトン開発して idd-codex に引き継ぐ場合の注意メモ

作成日: 2026-06-08

このメモは、今回の `feedman-ios` の進め方を後から再利用するための初期記録です。
実際にスケルトン作成、Issue 投入、PR レビューを進めた結果を追記して完成させる前提です。

## 今回の前提

- 仕様・デザイン・サーバー契約が先に存在する。
- iOS repo は初期状態では Git 管理されていない。
- idd-codex は GitHub Issue と repository template を前提に動く。
- 大きな初期スケルトンだけは人間/Codex が直接作り、その後の機能実装を idd-codex に分割投入する。

## 最初に決めるべきこと

- GitHub repo 名、visibility、default branch。
- bundle identifier、development team、signing 方針。
- Xcode project を手作りするか、XcodeGen/Tuist などで生成するか。
- Debug/Release の API base URL。
- custom URL scheme と Universal Links のどちらを v1 で使うか。現仕様は `feedman://auth/callback` 前提。
- server issue を同じ自動開発基盤で処理するか、別 repo/watcher で処理するか。

## スケルトン時点で用意したいもの

- `AGENTS.md`: Swift/iOS 向けに idd-codex template を書き換えたもの。
- `.codex/agents` と `.codex/rules`: idd-codex template。
- `.github/ISSUE_TEMPLATE/idd-codex-feature.yml`
- `.github/scripts/idd-codex-labels.sh`
- `README.md`: build, test, base URL, auth callback, mock mode の説明。
- 最小 Xcode project / app target / test target。
- `AppEnvironment` と protocol-based repository。
- mock repository と sample JSON fixture。
- design token と shared UI の置き場。

## Issue 分割の注意

- 1 Issue で 1 feature vertical slice にする。
- 依存関係を Issue 本文に明記する。
- API 契約と視覚基準の参照ファイルを必ず書く。
- 「v1 ではやらないこと」を毎回書く。特にキーワード通知、OPML、オフライン cache。
- server 依存がある Issue は `Depends on:` を本文に書き、未完了なら idd-codex に実装させない。
- 初期は mock mode で UI 実装を進め、API integration issue で real repository に差し替える。
- idd-codex / idd-claude は Issue 粒度が大きいと turn 上限（例: 60 turns）内に実装・検証・PR 作成まで到達できず fail しやすい。初期 backlog 作成時点で「機能単位」ではなく「実装可能な薄い縦切り」まで落とす。
- 大きな機能 Issue は Epic として残し、`codex-auto-dev` を付ける実装 Issue は子 Issue に分割する。Epic には `codex-auto-dev` を付けない。
- 実装 Issue の目安は、変更ファイル 3〜8 個、受入基準 3〜6 個、Architect が生成する tasks 3〜6 個程度。tasks が 8〜10 個に達しそうなら警告、11 個以上になりそうなら事前分割する。
- 「API 型」「Repository endpoint」「ViewModel state」「UI component」「integration polish」を同じ Issue に詰め込まない。必要なら mock 実装と real API integration を別 Issue にする。
- cross-feature state sync、認証 refresh、Safari、Keychain、push notification など横断関心事は、それだけで 1 Issue にする。
- `PER_TASK_LOOP_ENABLED=true` や `STAGE_CHECKPOINT_ENABLED=true` は fail を減らす補助にはなるが、大きすぎる Issue の代替にはならない。

## idd-codex 導入時の注意

- fork/mirror 由来の `docs/specs/<番号>-*` や `codex/issue-*` branch があると誤 resume の危険がある。
- 新規 repo では idd-codex template を入れた commit を先に main へ push する。
- 必須 label を作成してから watcher を起動する。
- watcher は repo ごとに `REPO` と `REPO_DIR` を明示して起動する。
- スケルトン直後の大きな未整理変更を残したまま watcher を動かさない。

## 今回追跡しておく観点

- スケルトン作成にどれだけ手作業が必要だったか。
- idd-codex が迷った仕様、質問した仕様。
- Issue 粒度が大きすぎた/小さすぎた箇所。
- Xcode project 変更と Codex の相性。
- SwiftUI preview/mock data が実装速度に効いたか。
- server dependency がある Issue の待ち方。
- PR review で繰り返し出た指摘。
