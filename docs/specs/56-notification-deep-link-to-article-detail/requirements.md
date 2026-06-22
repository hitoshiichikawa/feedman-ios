# Requirements Document

## Introduction

Issue #56 は Parent: #13 の子 Issue として、キーワード通知をタップしたときに該当記事の詳細 sheet を開く deep link 動線を定義する。
`design/SPEC-iOS.md` と `design/SERVER.md` では、通知 payload の `data.deep_link` が `feedman://items/{id}` を指し、タップ後にアプリ側が記事詳細を取得して表示することが示されている。
依存 Issue #54 は通知許可・APNs token 登録の foundation を、#35 は記事詳細 sheet と detail fetch / recoverable error 表示を担うため、本 Issue は通知応答から既存の記事詳細 presentation へ橋渡しする範囲に閉じる。
Issue コメントでは #35 / #54 が staged-for-release として依存解除済みであることが記録されており、人間による追加仕様回答はない。

## Requirements

### Requirement 1: Notification deep link recognition

**Objective:** As a Feedman user, I want 通知 payload の記事 deep link が安全に解釈される, so that 通知タップが意図しない画面や外部 URL を開かない

#### Acceptance Criteria

1. When a notification response contains `data.deep_link` with `feedman://items/{id}`, the app shall extract the item id for article detail navigation.
2. When a notification response contains `data.item_id` and `data.deep_link` is absent, the app shall create the article detail navigation target from the item id.
3. If the notification response contains a deep link with an unsupported scheme, host, or path, the app shall reject the notification navigation without presenting article detail.
4. If the extracted item id is empty or whitespace only, the app shall reject the notification navigation without presenting article detail.
5. If both `data.deep_link` and `data.item_id` are present and refer to different item ids, the app shall reject the notification navigation.
6. If both `data.deep_link` and `data.item_id` are present and refer to different item ids, the app shall expose a non-fatal error state.

### Requirement 2: Cold launch and foreground routing

**Objective:** As a Feedman user, I want 通知から起動しても既存起動中でも同じ記事詳細へ到達できる, so that アプリ状態に関係なく通知の文脈を継続できる

#### Acceptance Criteria

1. When the app is cold-launched from a valid article notification and session restoration succeeds, the app shall present article detail for the notification item id.
2. While session restoration is in progress after a notification launch, the app shall retain the pending article detail target without showing authenticated content early.
3. When the authenticated app receives a valid article notification response while running in background or foreground, the app shall present article detail for the notification item id.
4. When article detail is presented from a notification, the app shall close the drawer and use the existing article detail presentation surface.
5. When the user dismisses notification-launched article detail, the app shall clear that pending notification target so it is not reopened on the next app activation.

### Requirement 3: Authentication and session handling

**Objective:** As a Feedman user, I want 認証状態に応じて通知 deep link が安全に扱われる, so that 未認証のまま protected article data を表示しない

#### Acceptance Criteria

1. When a notification article target is received while the app is authenticated, the app shall request article detail using the current authenticated session boundary.
2. While the app is unauthenticated, the app shall not fetch article detail for a pending notification target.
3. When session restoration fails after a notification launch, the app shall show the unauthenticated login state without presenting article detail.
4. When the user completes login after a pending valid notification target exists in the same app session, the app shall present article detail for that target.
5. If article detail fetch returns an auth-required error, the app shall use the existing auth-required handling path instead of showing protected content.

### Requirement 4: Article detail loading and recoverable failure

**Objective:** As a Feedman user, I want 通知先の記事詳細が読み込まれ、失敗時は回復可能に扱われる, so that 通知タップの失敗からやり直せる

#### Acceptance Criteria

1. When a valid notification article target is presented, the article detail surface shall fetch full item detail for that item id.
2. When notification-launched detail loading is in progress, the article detail surface shall show the existing loading state.
3. When notification-launched detail loading succeeds, the article detail surface shall render the loaded article detail as the source of truth.
4. If notification-launched detail loading fails with a recoverable error, the article detail surface shall show a retry affordance.
5. When retry is activated after notification-launched detail loading fails, the article detail surface shall retry detail fetch for the same item id.
6. If notification-launched detail loading fails because the item no longer exists or is not accessible, the app shall show a dismissible error state.

### Requirement 5: Scope boundaries

**Objective:** As a Product Manager, I want #56 の責務を通知 deep link から記事詳細表示までに限定する, so that keyword notification 全体の未確定部分を暗黙に実装しない

#### Acceptance Criteria

1. The app shall not add keyword CRUD UI as part of this Issue.
2. The app shall not add notification category action buttons as part of this Issue.
3. The app shall not change server-side push worker, keyword matching, or notification payload contracts as part of this Issue.
4. The app shall not expose v1 scope-out keyword notification settings in the drawer as part of this Issue.
5. The app shall not introduce a separate article detail UI that bypasses the existing article detail sheet behavior.

## Non-Functional Requirements

### NFR 1: Reliability and compatibility

1. When notification deep link parsing is tested, the test suite shall cover valid `feedman://items/{id}`, invalid scheme, invalid path, empty item id, item id fallback, and conflicting deep link / item id cases.
2. When notification routing state is tested, the test suite shall cover cold-launch pending target retention, authenticated presentation, unauthenticated deferral, and pending target clearing after dismissal.
3. While running on iOS 16+, the notification deep link flow shall not crash when notification payload fields are missing, malformed, or duplicated.
4. The notification deep link flow shall not log access tokens, refresh tokens, APNs tokens, notification payload keywords, or personal article content.

### NFR 2: Scope and integration

1. The app shall keep notification deep link behavior compatible with the existing app shell article detail presentation.
2. The app shall keep article detail fetching and read marking behavior delegated to the existing article detail flow.
3. The app shall not require changes to `design/SPEC-iOS.md`, `design/SERVER.md`, prototype files, or other Issue specs as part of this Issue.

## Out of Scope

- Keyword CRUD UI / API integration.
- Keyword notification drawer route or settings sheet.
- Server-side keyword matching, push worker, FCM/APNs payload generation, and App Store release setup.
- Notification category action buttons, rich notification content, and custom notification UI.
- Universal Links for article items unless a later design decision replaces the documented `feedman://items/{id}` custom scheme.
- New article detail UI, new item detail API contract, or cross-screen state synchronization beyond existing article detail behavior.

## Open Questions

- 通知 payload で `data.deep_link` と `data.item_id` が両方存在し不一致の場合の最終仕様は未記載である。本要件では安全側として navigation を拒否する前提にしているが、サーバー側で不一致を発生させない契約にするか確認が必要である。
- 未認証状態で通知タップ後に login した場合、同一 app session 内の pending target を自動で開くか、login 後は通常 timeline に戻すかは Issue 本文に明記がない。本要件では通知意図を維持するため同一 session で開く前提にしている。
