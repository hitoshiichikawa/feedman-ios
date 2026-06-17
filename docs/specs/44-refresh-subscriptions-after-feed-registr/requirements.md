# Issue #44 Refresh subscriptions after feed registration 要件定義

## 概要

Issue #44 は Parent: #9 の子 Issue として、フィード登録が成功したあとに購読一覧と drawer のフィード一覧をアプリ再起動なしで更新する。
Issue #43 では `POST /api/feeds` によるフィード登録 repository / sheet と、登録成功後に AppShell が drawer feed list を再読み込みまたは反映できる境界が定義されている。
Issue #38 では `GET /api/subscriptions` による real subscriptions repository と drawer feed list の loading / success / empty / error / retry state が定義されている。

本 Issue はその 2 つの境界を接続し、登録成功イベントを契機に subscriptions reload を実行し、最新の購読一覧を drawer に反映することを固定する。
API 契約は `design/SPEC-iOS.md` と `design/SERVER.md` を正本とし、prototype の mock data shape は API 契約として扱わない。

Issue 本文の依存は `Depends on: #38, #43` である。
Issue コメントでは、依存 Issue が GitHub Issue state 上 open または `codex-staged-for-release` 相当であっても、owner から「進めてOKです。staged-for-releaseは進めるものとして処理してほしいです」と回答されている。
そのため本要件では、#38 と #43 の設計・実装境界を利用可能な前提として扱い、追加 blocker とはしない。

## スコープ

- フィード登録成功後に AppShell / drawer feed state が subscriptions reload を起動する要件を定義する。
- Reload は既存の `FeedRepository.subscriptions()` または #38 で定義された同等の subscriptions load 境界を利用する。
- Reload 成功時に drawer feed list を最新 subscriptions へ置き換え、新規登録フィードが response に含まれる場合は drawer に表示する。
- Reload 失敗時に登録成功自体を取り消さず、非破壊の retry guidance を表示できる state を定義する。
- Reload 中も drawer の global route entries と現在 route を壊さない。
- Unit test / ViewModel test で、登録成功イベント、reload 成功、reload 失敗、retry を実ネットワークなしで検証できるようにする。

## スコープ外

- `POST /api/feeds` の endpoint 内部、server contract、request / response shape の変更。
- フィード登録 sheet の入力、validation、重複 / rate-limit error mapping の再定義。
- `GET /api/subscriptions` の API contract、Subscription model、drawer mapping の再定義。
- 購読設定 sheet、購読解除、再開、fetch interval 変更、手動 fetch。
- 登録成功後の新規 feed への自動遷移必須化。
- フィード別記事一覧の API 接続、横断タイムライン、スター一覧、検索、記事詳細、既読 / スター mutation。
- キーワードプッシュ通知 UI、drawer 導線、push device / keyword API。
- `design/SPEC-iOS.md`、`design/SERVER.md`、確定済み他 Issue の `docs/specs/*` の変更。
- PR 作成、reviewer / project-manager 起動、実装コード変更。

## 受入基準

### Requirement 1: Registration success event integration

**Objective:** As a Feedman user, I want 登録完了後に購読一覧更新が始まる, so that 新しいフィードを再起動なしで見つけられる

1. When feed registration succeeds, the app shall emit or observe a registration-success event from the #43 registration boundary.
2. When AppShell receives the registration-success event, it shall request a subscriptions reload through the #38 drawer / subscriptions load boundary.
3. When registration succeeds, the app shall not require the user to restart the app or sign in again before the drawer can reflect the new subscription.
4. When registration succeeds, the sheet may show completion feedback before dismissing, but the subscriptions reload shall still be scheduled or started from an explicit app state transition.
5. When registration is cancelled, dismissed without success, or fails, the app shall not trigger the post-registration subscriptions reload.
6. If the success event includes registered feed identifiers or title, AppShell may use them for feedback, but the drawer feed list shall treat the subscriptions reload result as the source of truth.

### Requirement 2: Subscriptions reload behavior

**Objective:** As a Feedman user, I want 登録後の drawer が最新 subscriptions を取得する, so that 登録済みフィード一覧と server state がずれない

1. When feed registration completes, subscriptions shall reload.
2. When the reload starts, it shall call `FeedRepository.subscriptions()` or the existing subscriptions ViewModel load method rather than directly constructing `GET /api/subscriptions` in a View.
3. When the reload succeeds, the drawer feed section shall replace or reconcile its loaded feeds with the latest subscriptions result.
4. While reload is in progress, the drawer shall keep existing feed rows visible or show a lightweight loading state without blocking `すべての新着`、`お気に入り`、`アカウント` navigation.
5. When a reload is already in progress and another registration-success event arrives, the app shall avoid unsafe concurrent state mutation and shall produce deterministic final drawer state.
6. When the authenticated session is lost during reload, the app shall surface the same auth-required or recoverable state expected by #38 and shall not read or clear Keychain directly in the View.

### Requirement 3: Newly registered feed visibility

**Objective:** As a Feedman user, I want 登録したフィードが drawer に現れる, so that すぐにそのフィードへ移動できる

1. When the subscriptions reload result contains the newly registered feed, drawer shall show that feed row without app restart.
2. When the newly registered feed appears in drawer, selecting it shall use the stable feed identifier from subscriptions state for `AppShellRoute.feed(id:title:)`.
3. When the newly registered feed appears, drawer shall preserve the existing row rules for title, unread count, status, favicon / avatar, and accessibility.
4. When the registered feed is already present because it was a duplicate registration or server returned an existing subscription, drawer shall not render duplicate rows for the same stable feed identifier.
5. If the reload result does not contain the newly registered feed, the app shall keep a non-crashing state and may show non-destructive guidance that the list could not confirm the latest subscription yet.
6. When the current route is not the newly registered feed, reload success shall not forcibly navigate away from the user's current route unless a later Issue explicitly changes this behavior.

### Requirement 4: Reload failure and retry guidance

**Objective:** As a Feedman user, I want 登録成功後の一覧更新失敗を復旧できる形で知りたい, so that 登録が消えたと誤解せず retry できる

1. When reload fails after successful registration, app shall show non-destructive retry guidance.
2. When reload fails after successful registration, the app shall not present the registration itself as failed solely because the follow-up subscriptions reload failed.
3. When reload fails and previous drawer feeds exist, the drawer may keep those feeds visible, but it shall also expose that the latest reload failed.
4. When reload fails and no previous drawer feeds exist, the drawer shall show a failed state rather than an empty-subscriptions state.
5. When the retry action is activated, the app shall call the subscriptions load path again.
6. When retry succeeds, the drawer shall replace the failure guidance with the latest loaded subscriptions.
7. When retry fails again, the drawer shall remain usable for global routes and shall keep recoverable guidance.
8. The guidance shall be short Japanese user-facing text, for example `フィードは登録されましたが、一覧を更新できませんでした` plus retry affordance where practical.

### Requirement 5: AppShell state and presentation consistency

**Objective:** As a Feedman user, I want 登録完了、sheet dismissal、drawer 更新が一貫して動く, so that main app flow が不安定にならない

1. When the registration sheet completes successfully, the app shall dismiss it through the existing AppShell presentation state or allow the user to close it from a success state.
2. When success feedback such as toast or banner is shown, it shall distinguish registration success from subscriptions reload failure if both states occur.
3. When drawer is closed during reload, reload completion shall still update the drawer feed state for the next time it opens.
4. When drawer is open during reload, the feed section shall update in place without closing the drawer unexpectedly.
5. When the user is on a feed-specific route that remains present after reload, route state shall remain valid.
6. If the current feed-specific route is absent after reload, the shell shall use the safe fallback behavior defined by #28 / #38 and shall not crash.
7. When v1 drawer navigation is rendered, it shall not expose keyword notification settings or keyword notification drawer entries.

### Requirement 6: Repository and architecture boundaries

**Objective:** As a Developer, I want 登録後更新を既存 repository / ViewModel 境界で実装できる, so that View が network や auth details を持たない

1. The implementation shall keep Views from directly touching `URLSession`, Keychain, raw endpoint URLs, or token refresh logic.
2. The implementation shall use Swift Concurrency (`async` / `await`) for registration-success follow-up reload work.
3. The implementation shall keep post-registration refresh orchestration in AppShell / RegisterFeed / Subscriptions ViewModel or coordinator-like state, not in DesignSystem primitives.
4. The implementation shall not add a new server API or modify `/api/feeds` or `/api/subscriptions` semantics.
5. The implementation shall preserve #23 APIClient refresh retry behavior by using the existing real repository path.
6. The implementation shall keep Swift type names, identifiers, and file names in English.
7. If existing AppShell and RegisterFeed state boundaries cannot express the success event without large refactor, the implementer shall stop and ask for PM / Architect clarification rather than broadening scope silently.

### Requirement 7: Mock and testability

**Objective:** As a QA/Developer, I want 登録成功後更新を deterministic に検証できる, so that 実サーバーなしで regression を防げる

1. When using mock repositories, tests shall be able to simulate registration success followed by subscriptions reload success including the new feed.
2. When using mock repositories, tests shall be able to simulate registration success followed by subscriptions reload failure.
3. When using mock repositories, tests shall verify that registration failure does not trigger subscriptions reload.
4. When reload retry is invoked after failure, tests shall verify that the subscriptions load path is called again.
5. When multiple success events or duplicate reload requests occur, tests shall verify deterministic final state or guarded call count according to the chosen implementation.
6. Unit tests shall not depend on real network, real OAuth, real Keychain, real tokens, or personal data.
7. SwiftUI previews, if updated, shall use deterministic mock data and shall not introduce prototype-only fields such as `favicon_letter` or `favicon_color`.

## UI / 状態要件

- 登録成功後の更新中 state は drawer 全体を塞がず、global route entries を操作可能に保つ。
- 登録成功 feedback と subscriptions reload failure feedback は、同時に起きた場合でも意味が混ざらない文言にする。
- Reload failure guidance は空状態と区別し、登録後更新だけが失敗したことを短く伝える。
- Retry affordance は button または同等の明示操作にする。
- 新しく表示された feed row は #38 の drawer row layout、favicon / avatar handling、unread badge、status label、accessibility の規則に従う。
- Dynamic Type や長い feed title で、登録後に追加された row の title、status、unread badge、avatar が重ならないようにする。

## API / データ契約

- 登録 API は #43 の `POST /api/feeds` を利用する。本 Issue では request / response shape を変更しない。
- 購読 reload は #38 の `GET /api/subscriptions` を利用する。本 Issue では subscriptions response shape を変更しない。
- Drawer feed list の source of truth は reload 後の subscriptions state とする。
- 登録成功レスポンスに含まれる feed title / id は success feedback や reload target の参考に使ってよいが、drawer への最終反映は subscriptions reload result を優先する。
- `favicon_url` は `String?` のまま扱い、`data:` URL を `AsyncImage(url:)` に直接渡さない既存方針を維持する。
- API error は既存 `{ error: { code, message, category, action, details? } }` の typed error mapping を利用し、token 値や debug detail を user-facing UI に出さない。

## テスト要件

- AppShell / integration ViewModel test:
  - When registration success event is received, subscriptions shall reload.
  - When reload succeeds with a new feed, drawer state shall include the new feed without app restart.
  - When reload fails after registration success, state shall preserve registration success feedback and expose reload failure guidance.
  - When retry is invoked after reload failure, subscriptions shall load again.
  - When registration fails, subscriptions reload shall not be called.
  - When drawer is closed during reload, resulting feed state shall be available after drawer opens.
- Repository / mock test:
  - Mock registration success and mock subscriptions reload shall be composable without real network.
  - Mock subscriptions reload failure shall surface the same user-recoverable state path as real repository errors.
  - Duplicate feed identifiers in reload result shall not crash drawer state construction.
- UI state test:
  - Loading / success / failed-after-registration / retry states shall keep global route navigation available.
  - New feed row selection shall pass stable feed identifier and title into `AppShellRoute.feed(id:title:)`.
  - Error state after reload failure shall not be represented as empty subscriptions.
- macOS/Xcode 環境では以下を実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 非機能要件

### NFR 1: Compatibility

1. The implementation shall target iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and Swift Concurrency (`async` / `await`).
3. The implementation shall keep ViewModels / UI state that update SwiftUI on `@MainActor` where required.
4. The implementation shall not introduce automatic `Date` decoding or unrelated API model changes.

### NFR 2: Scope control

1. The implementation shall remain within Issue #44 の registration-success-to-subscriptions-refresh responsibility.
2. The implementation shall not rewrite #38 or #43 finalized requirements except through a separate design decision.
3. The implementation shall not introduce OPML、keyword notification、subscription settings、feed URL editing、or feed-scoped search UI.
4. The implementation shall not create PRs, invoke reviewer / project-manager agents, or perform release operations as part of this PM spec task.

### NFR 3: User safety and privacy

1. The implementation shall not log access tokens, refresh tokens, Authorization headers, or personal subscription contents beyond debug-safe diagnostics.
2. User-facing messages shall avoid exposing raw server debug details.
3. Reload failure after registration shall be non-destructive and shall not delete local drawer state or tokens.

## 実装境界

- RegisterFeed:
  - 登録成功 event を AppShell が観測できる形で発火する。
  - 登録 API の validation や error mapping は #43 の責務を維持する。
- AppShell:
  - 登録成功 event を受け取り、drawer / subscriptions load state に reload を依頼する。
  - Sheet dismissal、success feedback、reload failure guidance の presentation state を調停する。
- Subscriptions / Drawer:
  - #38 の subscriptions load path を使い、loaded / failed / retry state を保持する。
  - Drawer rendering は reload result を source of truth として feed rows を更新する。
- Core:
  - 本 Issue では新規 API model や endpoint contract を追加しない。
  - 必要な場合のみ、既存 repository protocol の成功 event / reload 呼び出しを接続するための最小の abstraction を追加する。

## 確認事項

- #38 と #43 は、Issue state が open または `codex-staged-for-release` 相当であっても、人間回答により本 Issue の前提として利用可能と扱う。
- 登録成功後の drawer 反映方法は、原則として subscriptions reload を必須とする。登録成功レスポンスをローカル挿入するだけでは、本 Issue の `subscriptions shall reload` を満たさない。
- 登録成功後に新規 feed route へ自動遷移することは必須にしない。v1 としては drawer に表示され、ユーザーが選択できることを固定する。
- Reload failure は登録失敗ではない。UI は登録成功と一覧更新失敗を区別して扱う。
- 現時点で追加の人間判断が必要な blocker はない。
