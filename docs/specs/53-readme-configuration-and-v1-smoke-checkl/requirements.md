# Issue #53 README configuration and v1 smoke checklist 要件定義

## 背景

Issue #53 は Parent: #12 の子 Issue として、開発者セットアップ、環境設定、v1 smoke test checklist を README へ文書化する。対象はドキュメント整備であり、Swift 実装、Xcode project 設定、CI workflow、App Store metadata、marketing copy は扱わない。

`README.md` には現時点で、Xcode で `Feedman` scheme を開いて iOS Simulator で実行すること、macOS での `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`、GitHub Actions の `iOS Tests` check、idd-codex watcher の `ST_CHECK_RUN_NAME` 設定が記載されている。一方で、`design/ZERO-TO-IDD-CODEX-NOTES.md` がスケルトン時点で用意したいものとして挙げている API base URL、auth callback、mock mode の説明、および Issue 本文が求める v1 smoke checklist は README で十分にまとまっていない。

`design/SPEC-iOS.md` と `design/SERVER.md` では、iOS v1 は `ASWebAuthenticationSession`、PKCE、`feedman://auth/callback?auth_code=...`、`POST /api/auth/token` / refresh / revoke、Bearer token、Keychain、SFSafariViewController、v1 主要画面を前提とする。API `baseURL` は環境で切り替える方針だが、Debug / Release / Staging / Local の正式な URL 文字列は既存仕様内では未確定である。

## Issue コメントの反映

`gh issue view 53 --comments` で確認したコメントは以下である。

- 依存 Issue #51 は `staged-for-release` になり、`codex-blocked` が自動解除された。Issue #53 はブロック解除済みとして扱う。
- Path Overlap Checker の edit path は `README.md` と `design/` である。
- ローカル Codex CLI が impl モードで処理を開始した。

README 記載内容、環境 URL、callback 方式、mock mode の詳細に関する追加の人間コメントはない。

## スコープ

- README に macOS/Xcode での開発セットアップ、build/test コマンド、CI check 名、手動検証コマンドを一貫して記載する。
- README に API base URL と auth callback の設定場所を、現行実装と確定仕様に基づいて記載する。
- README に v1 smoke test checklist を追加し、ログインから横断タイムライン、記事詳細、スター、フィード別 filter、フィード登録、検索、ログアウトまでの確認観点を明示する。
- README に mock / preview mode の位置づけを記載し、mock data の JSON 形を API 契約として扱わないことを明示する。
- 必要に応じて `design/ZERO-TO-IDD-CODEX-NOTES.md` へ、README に整備した内容の実績メモを追記してよい。

## スコープ外

- App Store metadata、marketing copy、screenshots、TestFlight、signing、archive、upload automation。
- Swift 実装、Xcode project 設定、Info.plist の URL scheme 変更、repository wiring の変更。
- GitHub Actions workflow や idd-codex watcher script の変更。
- 新規 server API、API response shape、Debug / Release の正式 URL 値の決定。
- キーワードプッシュ通知、OPML import/export、フィード URL 変更 UI、オフライン全文 cache、Feed-scoped search UI、WebView Cookie login fallback。

## 要件

### Requirement 1: macOS developer setup documentation

**Objective:** As a Developer, I want README の手順だけで Xcode project の開き方と検証コマンドを把握できる, so that 新しい作業者がローカルで同じ入口から build / test を確認できる

#### Acceptance Criteria

1. When README setup is followed on macOS, README shall instruct the developer to open `Feedman.xcodeproj` and run the `Feedman` scheme on an iOS Simulator.
2. When tests are run locally, README shall show the canonical command `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`.
3. If `iPhone 16` simulator is unavailable locally, README shall tell the developer to inspect available iPhone simulators with `xcrun simctl list devices available` and substitute an available simulator name.
4. While Linux or non-Xcode environments are used, README shall state that Xcode build/test cannot be run there and that macOS/Xcode is required for the canonical test.
5. When GitHub Actions is used as the automated gate, README shall keep the check run name `iOS Tests` visible and shall not contradict the existing CI section.

### Requirement 2: API base URL configuration documentation

**Objective:** As a Developer, I want API 接続先の設定場所と未決の値が README で明確になる, so that ローカル server、staging、production のどれへ接続しているかを誤解しない

#### Acceptance Criteria

1. When API base URL must be configured, README shall describe that the app uses `AppEnvironment.production(apiBaseURL:)` / `APIClient(baseURL:)` as the current app-side configuration boundary.
2. When no explicit URL is supplied by the app entry point, README shall document the current default `http://localhost:3000` as an implementation default, not as a confirmed production endpoint.
3. When Debug / Release / Staging / Local endpoint values are needed, README shall state that the final URL strings are 未決 and must be confirmed before treating them as release configuration.
4. When documenting API paths, README shall refer to `design/SPEC-iOS.md` and `design/SERVER.md` as the authoritative contracts instead of duplicating endpoint tables.
5. The README shall not invent production server URLs, secret names, tokens, bundle identifiers, or signing values that are not present in the source specifications.

### Requirement 3: Native auth callback configuration documentation

**Objective:** As a Developer, I want native auth callback の方式と設定確認箇所が README で分かる, so that Google login smoke test の失敗時に server / app のどちらを見るべきか判断できる

#### Acceptance Criteria

1. When native Google login is configured, README shall state that iOS v1 uses `ASWebAuthenticationSession` with `callbackURLScheme` `feedman`.
2. When OAuth completes in native flow, README shall state that the expected callback URL shape is `feedman://auth/callback?auth_code=...`.
3. When token exchange is described, README shall state that the app exchanges `auth_code` and PKCE `code_verifier` via `POST /api/auth/token`, then uses Bearer auth and refresh/revoke according to `design/SERVER.md`.
4. If Universal Links are considered, README shall state that v1 currently documents and tests the custom scheme path unless a later Issue changes that decision.
5. The README shall not document WebView Cookie login fallback as a supported v1 path.

### Requirement 4: mock / preview mode documentation

**Objective:** As a Developer, I want mock / preview data の位置づけが README で明確になる, so that UI preview と real API smoke test を混同しない

#### Acceptance Criteria

1. When README mentions mock or preview mode, it shall describe that mock repositories and preview data are for SwiftUI previews and tests, not the authoritative API contract.
2. When API contract questions arise, README shall point to `design/SPEC-iOS.md` and `design/SERVER.md` rather than prototype mock JSON.
3. When real v1 smoke testing is performed, README shall make clear that it requires a server implementing the native token auth and v1 API contracts.
4. The README shall not require real network, real Keychain, or real OAuth for unit tests that are already covered by mock repositories.

### Requirement 5: v1 smoke test checklist

**Objective:** As a QA/Developer, I want README に v1 の最小 smoke checklist がある, so that release 前や大きな merge 後に主要導線の生存確認を短時間で行える

#### Acceptance Criteria

1. When v1 smoke test is needed, README shall list login-to-timeline as the first check: Google login, token exchange, launch restoration as applicable, and cross-feed timeline display.
2. When timeline is checked, README shall include article detail sheet opening and original article opening through `SFSafariViewController` as smoke items.
3. When read/star behavior is checked, README shall include starring/un-starring from list or detail and verifying the Starred list reflects the change.
4. When feed-specific browsing is checked, README shall include opening a feed and switching all / unread / starred filter.
5. When feed registration is checked, README shall include registering a feed URL and confirming subscriptions / drawer refresh enough to see the new subscription.
6. When search is checked, README shall include global search with a non-empty query and opening a result detail.
7. When account flow is checked, README shall include account display and logout returning to the unauthenticated login state.
8. When smoke checklist is written, README shall keep destructive account deletion out of the default smoke checklist or mark it as destructive/manual-only.
9. When v1 scope is summarized, README shall keep keyword push notification and other v1 out-of-scope items out of the smoke checklist.

### Requirement 6: documentation scope and consistency

**Objective:** As a Maintainer, I want README の追加が既存仕様と矛盾しない, so that 後続 Issue が README を信頼できる入口として使える

#### Acceptance Criteria

1. When README is updated, it shall preserve existing CI / Branch and Release Flow / idd-codex operational details unless a direct conflict must be resolved.
2. When README references `design/ZERO-TO-IDD-CODEX-NOTES.md`, it shall treat it as setup history and operational notes, not as a replacement for `design/SPEC-iOS.md` or `design/SERVER.md`.
3. If `design/ZERO-TO-IDD-CODEX-NOTES.md` is updated, the change shall be limited to documenting that README now covers build/test, base URL, auth callback, mock mode, and smoke checklist.
4. The implementation shall not change `docs/specs/*` other than this Issue #53 spec during the implementation PR.

## 非機能要件

### NFR 1: Documentation quality

1. README additions shall be concise and executable, using exact commands where commands are required.
2. README user-facing text shall be consistent in Japanese / English style with the existing file.
3. README shall avoid leaking secrets, tokens, personal data, private URLs, or OAuth credentials.
4. README shall distinguish confirmed behavior from 未決事項.

### NFR 2: Traceability

1. README shall cite `design/SPEC-iOS.md` and `design/SERVER.md` for API/auth contracts.
2. README shall cite `design/ZERO-TO-IDD-CODEX-NOTES.md` only for setup checklist context where useful.
3. The implementation notes for Issue #53 shall record any README wording choice that depends on an unresolved configuration value.

### NFR 3: Scope control

1. The implementation shall remain a documentation change.
2. The implementation shall not add new app behavior, tests, CI workflow, or server requirements.
3. If setup documentation requires a configuration mechanism that does not exist, the implementation shall document the current boundary and 未決事項 instead of implementing a new mechanism.

## 実装境界

- 変更対象: `README.md`。
- 任意変更対象: `design/ZERO-TO-IDD-CODEX-NOTES.md` の追記のみ。
- 追加済み PM 成果物: `docs/specs/53-readme-configuration-and-v1-smoke-checkl/requirements.md`。
- 変更しない対象: Swift source、Xcode project、Info.plist、GitHub Actions workflow、既存 completed Issue の `docs/specs/*`。

## 未決事項

- Debug / Release / Staging / Local の正式な API base URL 文字列は未確定。README では現在の default と設定境界のみを書く。
- Production 用の bundle identifier、development team、signing、OAuth client ID、server 側 redirect URI / allowed scheme の具体値は未確定。本 Issue では値を作らない。
- Universal Links を v1 で採用するかは未確定。現時点の正本は custom scheme `feedman://auth/callback` である。
- README に `design/ZERO-TO-IDD-CODEX-NOTES.md` を更新した実績を追記するかは実装時判断でよいが、追記する場合もセットアップ履歴メモに留める。

## 検証

- Markdown として見出し、コードブロック、箇条書きが崩れていないことを確認する。
- README のコマンドが既存 AGENTS.md / README の canonical test command と一致していることを確認する。
- この Issue はドキュメント変更のため、Xcode test の実行は必須ではない。ただし実装者が環境を持つ場合は既存 README の canonical command を参考として実行してよい。
