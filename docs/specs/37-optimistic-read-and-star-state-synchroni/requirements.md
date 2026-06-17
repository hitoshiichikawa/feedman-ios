# Issue #37 Optimistic read and star state synchronization 要件定義

## 概要

Issue #37 は Parent: #7 の子 Issue として、一覧と記事詳細 sheet の間で既読 / スター状態を in-memory に同期し、mutation 失敗時に楽観反映を rollback する責務を扱う。

Issue 本文のゴールは「Read/star changes from list/detail stay consistent across visible screens with rollback on failure.」である。受入候補として、card からの star toggle、detail からの star toggle、mutation failure 時の rollback と error 表示が提示されている。

Issue コメントには Phase E の Triage edit_paths と処理開始コメントのみがあり、追加の仕様決定事項はない。Path Overlap Checker の edit path は `Feedman/` である。

本 Issue は #32 / #34 / #35 で明確にスコープ外とされた cross-screen optimistic update を実装対象にする。ただし、永続化は current in-memory repositories / app session state の範囲に閉じ、サーバー API や既存 specs の契約は変更しない。

## 参照仕様

- Issue #37 本文と `gh issue view 37 --comments` の既存コメント。
- `design/SPEC-iOS.md` §4.2, §4.3, §5.1, §5.4, §6, §10。
- `design/SERVER.md` §1 の Bearer 認証前提と既存 API 互換要件。
- `docs/specs/32-timeline-card-screen-ui/requirements.md`。
- `docs/specs/34-item-detail-and-state-repository-methods/requirements.md`。
- `docs/specs/35-article-detail-sheet-ui/requirements.md`。
- `docs/specs/26-shared-article-metadata-controls/requirements.md`。
- `docs/specs/27-reusable-loading-empty-error-toast-and-s/requirements.md`。

## 依存判断

Issue 本文の依存は `Depends on: #32, #34, #35` である。

- #32 により、横断タイムラインの card UI、read opacity、star control、card selection intent が利用可能になる。
- #34 により、`ItemRepository.updateItemState` から `PUT /api/items/{id}/state` の partial update を呼べる。
- #35 により、ArticleDetail sheet、sheet open 時の read marking、detail 内 star action の UI / ViewModel 境界が利用可能になる。
- 依存 Issue が完了していない場合、本 Issue の実装へ進まない。
- 実装開始時に作業 branch が #32 / #34 / #35 の成果物を含まない場合は、推測で補完せず Issue comment で確認する。

## スコープ

- 一覧と記事詳細 sheet の visible copies に対して、`isRead` / `isStarred` の effective state を in-memory で同期する。
- Timeline card からの star toggle を楽観反映し、`ItemRepository.updateItemState` の成功 / 失敗に応じて確定または rollback する。
- ArticleDetail sheet からの star toggle を楽観反映し、表示中の一覧 card と detail 表示を同じ state に揃える。
- ArticleDetail sheet open 時の `is_read: true` mutation を visible list copies にも楽観反映し、失敗時に rollback と error 表示を行う。
- 既存または依存成果物に open-original / external-link action があり、それが `is_read: true` を要求する場合、同じ read sync flow を再利用できるようにする。
- Mutation 失敗時は UI が表示可能な error state / toast / banner を出し、既存画面を破壊せずに前の状態へ戻す。
- ViewModel tests または小さな unit tests で optimistic update、cross-visible sync、rollback、error surface を検証する。

## スコープ外

- Current in-memory repositories / app session state を超える永続化。
- App relaunch 後に optimistic overlay を復元する仕組み。
- サーバー API、`design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、他 Issue の確定済み `docs/specs/*` の変更。
- `PUT /api/items/{id}/state` 以外の新規 state mutation API。
- 一括既読、feed unread count の楽観更新、server sync endpoint、background sync。
- SFSafariViewController presenter の新規実装。
- フィード別一覧、スター一覧、検索結果など未実装画面の新規作成。ただし実装時点で同じ item id の visible copy が存在する既存画面は、過度な feature 拡張なしに同じ in-memory state を参照できる設計にしてよい。
- Prototype mock data の JSON 形を API 契約として扱うこと。
- 実装コードの変更。

## 要件

### Requirement 1: In-memory article state synchronization boundary

**Objective:** As a Feedman user, I want 同じ記事の既読 / スター状態が表示中の一覧と詳細で揃う, so that 操作した直後に画面間の状態差分で混乱しない

#### Acceptance Criteria

1. The implementation shall provide an in-memory state synchronization boundary for item `isRead` and `isStarred` values.
2. The synchronization boundary shall be scoped to the current app session, ViewModel graph, repository mock, or app environment state, and shall not persist state to disk.
3. When an `ItemSummary` becomes visible in a list, the visible state shall be derived from repository data plus any newer in-memory override for the same item id.
4. When an `ItemDetail` becomes visible in the detail sheet, the visible state shall be derived from detail data plus any newer in-memory override for the same item id.
5. When repository data is refreshed while no local mutation is pending for the same item id, the synchronization boundary may accept the refreshed server state as the new baseline.
6. When repository data is refreshed while a local mutation is pending for the same item id, the refresh shall not erase the pending optimistic state before the mutation result is known.
7. The synchronization boundary shall only own mutable read / star display state and shall not become the source of truth for title, content, link, favicon, published date, or hatebu metadata.
8. The implementation shall not introduce a global singleton unless it is already the established project pattern for app-scoped UI state.

### Requirement 2: Optimistic read synchronization

**Objective:** As a Feedman user, I want detail を開いた記事が一覧でもすぐ既読表示になる, so that 読んだ記事が visible screens に即時反映される

#### Acceptance Criteria

1. When the ArticleDetail sheet opens an unread item and requests `is_read: true`, visible copies of the same item shall update optimistically to read before the repository mutation completes.
2. When the read optimistic update is applied, Timeline cards for the same item id shall reflect read opacity / accessibility state consistently with #32 behavior.
3. When the detail sheet is visible for the same item id, the detail read state shall also reflect the optimistic read value.
4. When the read mutation succeeds, the optimistic read state shall be kept as the confirmed visible state.
5. If the read mutation fails, visible copies that were changed by that mutation shall roll back to their previous read value.
6. If the read mutation fails, the UI shall surface a non-blocking error and shall not dismiss the detail sheet automatically.
7. When the opened item is already read, the implementation may skip the mutation or send an idempotent `is_read: true` request, but it shall not mark the item unread.
8. When an existing open-original or external-link action requests read marking, it shall use the same read synchronization behavior without requiring this Issue to implement Safari presentation.

### Requirement 3: Optimistic star synchronization from list and detail

**Objective:** As a Feedman user, I want card と detail のどちらでスターを切り替えても表示中の同じ記事が同じ状態になる, so that star 操作の結果を一貫して確認できる

#### Acceptance Criteria

1. When the user toggles star from a Timeline card, all visible copies of the same item id shall update optimistically to the requested star value.
2. When the user toggles star from ArticleDetail, all visible copies of the same item id shall update optimistically to the requested star value.
3. When a star optimistic update is applied from a card while the detail sheet for the same item is visible, the detail star control shall reflect the same requested value.
4. When a star optimistic update is applied from detail while a card for the same item is visible, the card star control shall reflect the same requested value.
5. When the star mutation succeeds, the optimistic star state shall be kept as the confirmed visible state.
6. If the star mutation fails, visible copies that were changed by that mutation shall roll back to their previous star value.
7. If the star mutation fails, the UI shall surface a non-blocking error that communicates the star change was not saved.
8. When the star control is activated inside a tappable card, the action shall not trigger the card body open action.
9. While a star mutation for an item is in flight, repeated taps for the same item shall be deterministic by disabling the control, serializing mutations, or using an explicit latest-intent policy.

### Requirement 4: Repository mutation contract

**Objective:** As a Developer, I want optimistic UI orchestration が Repository 契約を壊さず state update を呼べる, so that API boundary と UI state boundary を分離できる

#### Acceptance Criteria

1. When read state is committed to the server, the implementation shall call `ItemRepository.updateItemState` with a partial body containing `is_read`.
2. When star state is committed to the server, the implementation shall call `ItemRepository.updateItemState` with a partial body containing `is_starred`.
3. When only read state changes, the mutation request shall not force an `is_starred` value.
4. When only star state changes, the mutation request shall not force an `is_read` value.
5. When both read and star state are intentionally committed together by a caller, the request may include both fields while preserving the partial update semantics from #34.
6. The View and ViewModel shall not construct `URLSession` requests directly for item state updates.
7. The implementation shall rely on the existing APIClient / AuthRepository refresh behavior for authenticated retry and shall not implement endpoint-specific token refresh logic.
8. If repository mutation fails with a typed Feedman error, the caller shall preserve enough typed context to map it to UI-presentable error feedback.
9. The implementation shall not require the server to return an updated item body for state mutation success.

### Requirement 5: Rollback correctness and concurrent mutation handling

**Objective:** As a Developer, I want rollback が後続操作を壊さない, so that optimistic update failure handling remains predictable

#### Acceptance Criteria

1. When an optimistic mutation starts, the implementation shall capture the previous visible value for the field being changed.
2. If a mutation fails and no newer mutation has superseded that field for the same item id, the implementation shall roll back that field to the captured previous value.
3. If a mutation fails after a newer successful or pending mutation has changed the same field for the same item id, the rollback shall not overwrite the newer intended state.
4. When read and star mutations for the same item are independent, failure of one field shall not roll back the other field unless both fields were part of the same failed mutation.
5. While any mutation is pending for an item, list refresh or detail reload shall continue to render the effective optimistic state for fields still pending.
6. When all pending mutations for an item complete and a later repository refresh returns server state, the visible state may reconcile to that refreshed server state.
7. When the user navigates away from a screen and returns within the same app session, the in-memory state shall remain consistent if the owning ViewModel / app state is still alive.
8. When an item appears more than once in visible loaded collections, every visible copy shall converge to the same effective `isRead` and `isStarred` state.

### Requirement 6: UI feedback and accessibility

**Objective:** As a Feedman user, I want mutation failure を理解できる, so that 表示が戻った理由と保存失敗を認識できる

#### Acceptance Criteria

1. If read marking fails, the app shall show a non-blocking error equivalent to「既読状態を更新できませんでした」or a similarly clear Japanese message.
2. If star update fails, the app shall show a non-blocking error equivalent to「スターを更新できませんでした」or a similarly clear Japanese message.
3. When error feedback is shown, it shall not cover or permanently block primary navigation, card scrolling, or detail dismissal.
4. When shared toast / banner primitives are available, the implementation should use them instead of creating an unrelated error presentation style.
5. When a star control changes optimistically, its accessibility selected / unselected state shall match the visible optimistic state.
6. When read state changes optimistically, reduced opacity shall not be the only accessibility signal if an accessibility read / unread value exists in the current card implementation.
7. When a mutation is in flight and the implementation disables the star control, the disabled state shall be communicated accessibly.
8. The implementation shall support light mode, dark mode, narrow widths, and Dynamic Type without overlapping card actions, detail footer actions, or error feedback.

### Requirement 7: Integration with visible screens

**Objective:** As a Feedman user, I want existing Timeline / Feed / Search / ArticleDetail behavior to gain sync without unrelated feature changes, so that this Issue stays focused

#### Acceptance Criteria

1. When the Timeline screen renders cards from `ItemSummary`, it shall use the synchronized effective read / star state for visible card display.
2. When a feed item list screen renders cards from `ItemSummary`, it should use the same synchronized effective read / star state where the screen is already implemented.
3. When GlobalSearch results render `ItemSearchHit` values with `isRead` / `isStarred`, they should continue to accept item state changes through the existing `applyItemStateChange` path and should not regress.
4. When the Timeline card star action is invoked, it shall route through the synchronized optimistic star update flow.
5. When an implemented card body opens ArticleDetail through the existing selection boundary, opening detail shall be able to trigger the synchronized read update flow.
6. When ArticleDetail renders `ItemDetail`, it shall use the synchronized effective read / star state for visible controls.
7. When ArticleDetail read marking on open succeeds or fails, the result shall be reflected consistently in both sheet-local state and visible list state.
8. When ArticleDetail star action succeeds or fails, the result shall be reflected consistently in both sheet-local state and visible list state.
9. When ArticleDetail is dismissed, dismissal shall not leave stale selected detail state that overrides the synchronized state for later openings.
10. The integration shall not add keyword notification UI, feed-scoped search UI, or new route types.

### Requirement 8: Tests and verification expectations

**Objective:** As a QA / Developer, I want optimistic state sync を単体テストで固定できる, so that list/detail regressions を早く検出できる

#### Acceptance Criteria

1. When star toggles from a card and repository mutation succeeds, tests shall verify card state and visible detail state both show the new star value.
2. When star toggles from detail and repository mutation succeeds, tests shall verify detail state and visible list state both show the new star value.
3. When star toggles from a card and repository mutation fails, tests shall verify visible copies roll back and error feedback state is exposed.
4. When star toggles from detail and repository mutation fails, tests shall verify visible copies roll back and error feedback state is exposed.
5. When detail opens an unread item and read mutation succeeds, tests shall verify list and detail effective state become read.
6. When detail opens an unread item and read mutation fails, tests shall verify list and detail effective state roll back to unread and error feedback state is exposed.
7. When read and star mutations overlap for the same item, tests shall verify failure rollback for one field does not incorrectly overwrite the other field.
8. When a list refresh returns stale state while a mutation is pending, tests shall verify the visible optimistic state remains effective until mutation completion.
9. Tests shall use mock repositories and dummy item ids / tokens only, without real network, real Keychain, real OAuth, or personal data.
10. While macOS/Xcode is available, the implementer shall run `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` or document why it could not be run.

## 非機能要件

### NFR 1: Architecture and maintainability

1. The implementation shall support iOS 16+ and SwiftUI.
2. The implementation shall follow MVVM + Repository and keep Views away from direct `URLSession`、Keychain、Bearer token、and request body encoding.
3. UI-facing state coordinators / ViewModels shall be `@MainActor` where required.
4. The synchronization boundary should live under `Feedman/Core/State` or an existing app-state location if one is already established.
5. Feature wiring should remain focused under `Feedman/Features/Timeline` and `Feedman/Features/ArticleDetail` where practical.
6. Swift の型名、識別子、ファイル名は English にする。

### NFR 2: Scope control

1. The implementation shall remain within Issue #37 の optimistic read / star synchronization responsibility.
2. The implementation shall not modify `design/SPEC-iOS.md`、`design/SERVER.md`、prototype files、または他 Issue の確定済み `docs/specs/*`。
3. The implementation shall not introduce server contract changes or treat prototype mock JSON as API contract.
4. The implementation shall not add persistence beyond current in-memory repositories / app session state.
5. The implementation shall not include implementation code changes in the design PR.

### NFR 3: Security and error handling

1. The implementation shall not commit real tokens, Secret、個人情報、または実ユーザーの記事データ。
2. Repository errors shall not be swallowed silently.
3. Auth-required failures shall be exposed through existing app-level auth handling boundaries where available, not converted into apparent mutation success.
4. Error messages shown to users shall be Japanese and concise.
5. Logs and tests shall use dummy identifiers and shall not include private article data.

## 実装境界

- `ItemSummary` / `ItemDetail` の API model 自体を mutable global model に変える必要はない。表示時に effective state を合成する approach を優先する。
- Synchronization state は item id を key にし、`isRead` / `isStarred` の baseline、optimistic override、pending mutation metadata を扱えるようにする。
- Rollback は field 単位で行い、read failure が star を戻したり、star failure が read を戻したりしないようにする。
- #34 の partial update 契約を維持し、成功 response body は要求しない。
- #35 の sheet-local read / star state は、本 Issue で list-visible state と同じ synchronization boundary を通す。
- #32 の local-only star behavior は、本 Issue で repository mutation + rollback 付きの behavior に置き換える。
- 日付文字列は RFC3339 `String` のまま保持し、表示層で整形する。`Date` 自動 decode へ変更しない。
- Favicon の `data:` URL handling、article metadata controls、shared star control は既存 component を利用し、本 Issue で再実装しない。

## テスト観点

- In-memory synchronizer が item id ごとに read / star effective state を返すこと。
- Repository data の初期 state と optimistic override の優先順位。
- Card star toggle success / failure。
- Detail star toggle success / failure。
- Detail open read marking success / failure。
- 同一 item id が list と detail に同時表示される場合の同期。
- Mutation failure 時の field-specific rollback。
- Newer mutation がある場合に古い failure rollback が後続 state を壊さないこと。
- Pending mutation 中の refresh / detail reload で optimistic state が消えないこと。
- Error feedback state が ViewModel から検証可能であること。
- Mock repository が requested partial state values を記録し、configured failure を返せること。

## 確認事項

- #37 の design PR は設計成果物のみを含め、実装コードへは進まない。
- Star 連打時は、実装複雑度を抑えるため、同一 item / field の pending mutation 中は control を disable する方針を第一候補とする。
- Feed unread count の楽観更新は本 Issue の範囲外とし、必要なら別 Issue に分割する。
