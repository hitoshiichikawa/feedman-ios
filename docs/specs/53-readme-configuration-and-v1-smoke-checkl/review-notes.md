# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-18T07:13:56Z -->

## Reviewed Scope

- Branch: codex/issue-53-impl-readme-configuration-and-v1-smoke-checkl
- HEAD commit: bd432a4ed6339ff7e9d3d057bd71ac3b7bd84ffe
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `README.md:22` で `Feedman.xcodeproj` と `Feedman` scheme / iOS Simulator の実行手順を記載。
- 1.2 — `README.md:25`-`README.md:29` で canonical test command を記載。
- 1.3 — `README.md:31`-`README.md:36` で `xcrun simctl list devices available` と simulator 名の読み替えを記載。
- 1.4 — `README.md:38`-`README.md:39` で Linux / non-Xcode 環境では Xcode build/test 不可、macOS + Xcode 必須と記載。
- 1.5 — `README.md:101`-`README.md:116` で CI check run 名 `iOS Tests` と既存 ST gate 設定を維持。
- 2.1 — `README.md:45`-`README.md:46` で `AppEnvironment.production(apiBaseURL:)` / `APIClient(baseURL:)` を設定境界として記載。既存実装は `Feedman/Core/AppEnvironment.swift:137`-`Feedman/Core/AppEnvironment.swift:147`。
- 2.2 — `README.md:46`-`README.md:48` で default `http://localhost:3000` を production endpoint ではない実装 default と記載。既存実装は `Feedman/Core/AppEnvironment.swift:137`-`Feedman/Core/AppEnvironment.swift:139`。
- 2.3 — `README.md:50`-`README.md:51` で Debug / Release / Staging / Local URL が未決であることを記載。
- 2.4 — `README.md:53`-`README.md:55` で `design/SPEC-iOS.md` / `design/SERVER.md` を正本とし endpoint table を重複管理しないと記載。
- 2.5 — `README.md:45`-`README.md:55` の範囲で未確定の production URL、secret、token、bundle identifier、signing 値を作っていないことを確認。
- 3.1 — `README.md:59`-`README.md:60` で `ASWebAuthenticationSession` と `callbackURLScheme` `feedman` を記載。既存実装は `Feedman/Features/Login/LoginViewModel.swift:48`-`Feedman/Features/Login/LoginViewModel.swift:82`。
- 3.2 — `README.md:62`-`README.md:66` で callback URL shape `feedman://auth/callback?auth_code=...` を記載。
- 3.3 — `README.md:68`-`README.md:69` で `auth_code` / PKCE `code_verifier` の `POST /api/auth/token` 交換、Bearer / refresh / revoke を記載。
- 3.4 — `README.md:70`-`README.md:71` で v1 README / smoke test は custom scheme を対象にすると記載。
- 3.5 — `README.md:71`-`README.md:72` で WebView Cookie login fallback は supported path ではないと記載。
- 4.1 — `README.md:76`-`README.md:77` で mock repositories / preview data は SwiftUI preview と unit test 用と記載。
- 4.2 — `README.md:76`-`README.md:78` で mock/prototype JSON を API contract とせず正本 spec を参照すると記載。
- 4.3 — `README.md:80`-`README.md:81` で real v1 smoke test には native token auth と v1 API contract 実装 server が必要と記載。
- 4.4 — `README.md:80` で unit test は mock repositories を使える範囲では real network / Keychain / OAuth に依存させないと記載。
- 5.1 — `README.md:87`-`README.md:88` の checklist 先頭で Google login、token exchange、session restore、横断タイムライン表示を記載。
- 5.2 — `README.md:89`-`README.md:90` で記事詳細 sheet と `SFSafariViewController` による元記事表示を記載。
- 5.3 — `README.md:91` で list/detail からの star / unstar と Starred list 反映を記載。
- 5.4 — `README.md:92` で feed を開き all / unread / starred filter を切り替える確認を記載。
- 5.5 — `README.md:93` で feed URL 登録と subscriptions / drawer refresh 後の確認を記載。
- 5.6 — `README.md:94` で non-empty query の global search と結果詳細を開く確認を記載。
- 5.7 — `README.md:95` で account 表示と logout 後の unauthenticated login state を記載。
- 5.8 — `README.md:96`-`README.md:97` で Account deletion を default smoke checklist から外し destructive manual-only と記載。
- 5.9 — `README.md:83`-`README.md:97` の smoke checklist に keyword push notification など v1 scope 外項目が含まれていないことを確認。
- 6.1 — `README.md:99`-`README.md:160` で CI / Branch and Release Flow / idd-codex operational details が維持されていることを確認。
- 6.2 — `README.md:53`-`README.md:55` で `design/ZERO-TO-IDD-CODEX-NOTES.md` を setup history とし、API / auth contract の正本ではないと記載。
- 6.3 — `design/ZERO-TO-IDD-CODEX-NOTES.md` は差分なし。該当条件は発生していない。
- 6.4 — `git diff --name-status develop..HEAD` で `docs/specs/*` の変更が Issue #53 spec dir のみであることを確認。
- NFR 1.1 — `README.md:25`-`README.md:36` と `README.md:118`-`README.md:124` に実行可能な exact command を記載。
- NFR 1.2 — `README.md:20`-`README.md:124` の追加文は既存 README と同じ日本語 / English 混在スタイルで記載。
- NFR 1.3 — `README.md:45`-`README.md:97` に secret、token 実値、個人情報、private URL、OAuth credential の記載なし。
- NFR 1.4 — `README.md:47`-`README.md:51` で implementation default と未決事項を区別。
- NFR 2.1 — `README.md:53` と `README.md:78` で `design/SPEC-iOS.md` / `design/SERVER.md` を参照。
- NFR 2.2 — `README.md:54`-`README.md:55` で `design/ZERO-TO-IDD-CODEX-NOTES.md` を setup history としてのみ参照。
- NFR 2.3 — `docs/specs/53-readme-configuration-and-v1-smoke-checkl/impl-notes.md:8` で未決 configuration 値に関する README wording choice を記録。
- NFR 3.1 — `git diff --stat develop..HEAD` は README と Issue #53 spec notes のみで、Swift 実装差分なし。
- NFR 3.2 — `git diff --name-status develop..HEAD` で app behavior、test、CI workflow、server requirement の追加なし。
- NFR 3.3 — `README.md:45`-`README.md:51` で新しい設定機構を実装せず、現在の境界と未決事項を記載。

## Findings

なし

## Summary

差分は `README.md` と Issue #53 spec dir の成果物追加に限定され、AC 未カバー / missing test / boundary 逸脱は検出しませんでした。`tasks.md` と `design.md` は対象 spec dir に存在しなかったため、requirements と差分に基づいて判定しました。

RESULT: approve
