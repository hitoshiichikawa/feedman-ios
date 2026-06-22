# Design Document

## Overview

Issue #55 は、次フェーズのキーワードプッシュ通知に向けて、iOS から `/api/keywords` を操作する Core repository と、ユーザーが keyword を管理する SwiftUI settings sheet を追加する。既存の #54 APNs device registration foundation は再設計せず、keyword CRUD と settings UI の境界に変更範囲を閉じる。

**Purpose**: この機能は「通知対象にしたい記事タイトル keyword を自分で管理できる」価値を Feedman の authenticated user に提供する。
**Users**: Feedman user が AppShell drawer から「キーワード通知」を開き、keyword の追加・編集・有効化/無効化・削除を行う workflow で利用する。
**Impact**: 現在の iOS app は `/api/devices` foundation までを持つ状態であり、これを `/api/keywords` repository と settings sheet によって keyword 管理まで進める。ただし server-side matching worker、push delivery、notification deep link は後続 Issue の責務として残す。

### Goals

- `/api/keywords` の list/create/update/delete を mockable repository 境界として実装できる設計にする。
- Keyword settings ViewModel が loading / empty / loaded / recoverable error / mutation feedback を扱える状態機械を定義する。
- AppShell から keyword settings sheet を開ける導線を追加し、既存 route state を壊さない。
- Duplicate / rate-limit / auth-required / network failure を UI 表示可能な guidance に変換する。
- Repository と ViewModel の主要分岐を XCTest で実ネットワークなしに検証する。

### Non-Goals

- Server-side matching worker、push job enqueue、FCM/APNs 配信。
- Notification tap deep link (`feedman://items/{id}`) の routing 完成。
- `/api/devices`、APNs token、logout unregister policy の再設計。
- Body/content keyword matching、feed-scoped keyword、複数 scope UI。
- OPML、feed-scoped search、offline full-text cache。
- API 契約の変更や prototype mock JSON shape の採用。

## Architecture

### Existing Architecture Analysis

- 既存アーキテクチャは MVVM + Repository。`Feedman/Core` に API 型、API client、repository protocol / implementation を置き、Feature View / ViewModel は直接 `URLSession` や Keychain を触らない。
- `APIClient` は Bearer token 付き request と 401 refresh retry hook を既に持つ。Keyword repository はこの既存境界に乗せ、Notifications feature に refresh logic を持ち込まない。
- `Feedman/Features/Notifications` には #54 の `NotificationPermissionCoordinator` と `APNsDeviceRegistrationService` がある。Issue #55 では同ディレクトリに keyword settings UI / ViewModel を追加するが、device registration state machine は変更しない。
- `RootView` / `AppShellState` は sheet presentation を `AppShellPresentation` で管理している。Keyword settings は同じ presentation 境界に追加し、Timeline / Feed / Search などの route state を保持する。
- `Feedman/DesignSystem/SharedPrimitives.swift` には `FeedmanSheetShell`、loading、empty、recoverable error、banner、toast があるため、keyword settings はこれらを再利用する。

### Architecture Pattern & Boundary Map

```mermaid
flowchart LR
    Drawer[AppShell Drawer] --> ShellState[AppShellState]
    ShellState --> Sheet[KeywordSettingsSheet]
    Sheet --> VM[KeywordSettingsViewModel]
    VM --> RepoProtocol[KeywordRepository]
    RepoProtocol --> APIRepo[APIClientKeywordRepository]
    APIRepo --> APIClient[APIClient]
    APIClient --> Server[/api/keywords]
    RepoProtocol --> MockRepo[MockKeywordRepository]
```

**Architecture Integration**:
- 採用パターン: MVVM + Repository。既存 Feature と同じく View は ViewModel に action を渡し、ViewModel が repository protocol を呼ぶ。
- ドメイン／機能境界: `Feedman/Core` は API model と repository contract、`Feedman/Features/Notifications` は keyword settings UI state と presentation、`Feedman/Features/AppShell` は入口と sheet 管理のみを担当する。
- 既存パターンの維持:
  - Bearer auth と 401 refresh retry は `APIClient` に委譲する。
  - UI feedback は `FeedmanBannerView` / `FeedmanRecoverableErrorView` / `FeedmanToastCenter` を使う。
  - `@MainActor` ViewModel で UI state を保持する。
- 新規コンポーネントの根拠:
  - `KeywordRepository` は `/api/keywords` が `FeedRepository` と責務が異なり、Notifications feature からも Core 契約として使うため必要。
  - `KeywordSettingsViewModel` は add/edit/toggle/delete の operation state と error mapping を View から分離するため必要。
  - `KeywordSettingsSheet` は AppShell から開く次フェーズ UI の具体 surface として必要。

### Technology Stack

| Layer | Choice / Version | Role in Feature | Notes |
|-------|------------------|-----------------|-------|
| Frontend / CLI | SwiftUI / iOS 16+ | Keyword settings sheet、drawer entry、input/toggle/delete UI | `.sheet` + detents、existing DesignSystem を再利用 |
| Backend / Services | Existing Feedman API | `/api/keywords` CRUD | Server 実装変更はスコープ外 |
| Data / Storage | In-memory UI state | Keyword list、operation state、error presentation | 永続 local cache は持たない |
| Messaging / Events | AppShell presentation state | Drawer tap → sheet presentation、toast/auth guidance | Push delivery event はスコープ外 |
| Infrastructure / Runtime | `APIClient`, `URLSession`, XCTest | Bearer request、401 refresh retry、mock transport tests | View は直接 network を触らない |

## File Structure Plan

### Directory Structure

```text
Feedman/
├── Core/
│   ├── APIModels.swift                       # KeywordResponse / KeywordCreateRequest / KeywordUpdateRequest を追加
│   ├── KeywordRepository.swift               # KeywordRepository protocol, APIClientKeywordRepository, MockKeywordRepository
│   └── AppEnvironment.swift                  # keywordRepository injection / production / preview wiring を追加
├── Features/
│   ├── AppShell/
│   │   ├── AppShellState.swift               # AppShellPresentation.keywordSettings を追加
│   │   └── RootView.swift                    # drawer entry と KeywordSettingsSheet presentation を追加
│   └── Notifications/
│       ├── KeywordSettingsViewModel.swift    # loading / mutation state / error mapping
│       └── KeywordSettingsSheet.swift        # keyword settings sheet UI
└── DesignSystem/
    └── SharedPrimitives.swift                # 原則変更なし。不足時のみ既存 primitive の小補強

FeedmanTests/
├── KeywordRepositoryTests.swift              # API request/decode/refresh retry behavior
├── KeywordSettingsViewModelTests.swift       # state machine, mutation, error mapping
└── AppShellStateTests.swift                  # keyword settings presentation 追加分
```

### Modified Files

- `Feedman/Core/APIModels.swift` — keyword API item と create/update request 型を追加する。日付自動 decode は増やさない。
- `Feedman/Core/AppEnvironment.swift` — `keywordRepository` を injectable dependency として追加し、production では `APIClientKeywordRepository`、preview/test では `MockKeywordRepository` を使う。
- `Feedman/Features/AppShell/AppShellState.swift` — `AppShellPresentation.keywordSettings` と `presentKeywordSettings()` を追加する。
- `Feedman/Features/AppShell/RootView.swift` — drawer/footer entry から keyword settings sheet を開き、sheet content に `KeywordSettingsSheet` を接続する。
- `Feedman.xcodeproj/project.pbxproj` — 新規 Swift / test files を target に追加するため更新する。

## Requirements Traceability

| Requirement | Summary | Components | Interfaces | Flows |
|-------------|---------|------------|------------|-------|
| 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 | Keyword API model contract | KeywordAPIModels, KeywordRepository | Codable models | Decode / request construction |
| 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8 | Repository CRUD behavior | KeywordRepository | Service/API | list/create/update/delete |
| 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7 | ViewModel state | KeywordSettingsViewModel | State/Service | open/load/retry/mutation |
| 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8 | Mutation validation and guidance | KeywordSettingsViewModel, KeywordSettingsSheet | State | add/edit/toggle/delete failure |
| 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8 | Settings UI | KeywordSettingsSheet | State | sheet rendering and actions |
| 6.1, 6.2, 6.3, 6.4, 6.5 | AppShell integration | AppShellKeywordSettingsPresentation | State | drawer -> sheet -> dismiss |
| 7.1, 7.2, 7.3, 7.4, 7.5, 7.6 | Mocking and tests | KeywordRepository, KeywordSettingsViewModel | Service/State | XCTest with mocks |
| 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8 | Accessibility/security/constraints | KeywordSettingsSheet, AppShellKeywordSettingsPresentation | State | accessibility, no secret logging, verification |

## Components and Interfaces

### Core

#### KeywordAPIModels

| Field | Detail |
|-------|--------|
| Intent | `/api/keywords` の canonical fields と request body を表す |
| Requirements | 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 7.3 |

**Responsibilities & Constraints**
- `id`, `term`, `scope`, `enabled`, `hits` を API field として保持する。
- `scope` は現 UI では `"title"` のみ create/update に使う。
- `hits` は UI 表示用の数値として保持し、client 側で集計しない。
- Response wrapper ambiguity は repository decode 境界で吸収し、UI に prototype-only model を渡さない。

**Dependencies**
- Inbound: `KeywordRepository` — decode / encode に利用 (Critical)
- Outbound: `Codable` — JSON encode/decode (Critical)
- External: Feedman API — `/api/keywords` field contract (Critical)

**Contracts**: Service [ ] / API [x] / Event [ ] / Batch [ ] / State [ ]

##### API Contract

```swift
struct KeywordResponse: Codable, Equatable {
    let id: String
    let term: String
    let scope: String
    let enabled: Bool
    let hits: Int
}

struct KeywordCreateRequest: Codable, Equatable {
    let term: String
    let scope: String
    let enabled: Bool
}

struct KeywordUpdateRequest: Codable, Equatable {
    let term: String?
    let enabled: Bool?
}
```

- Preconditions: `term` は ViewModel で trim 済み、空文字ではない。
- Postconditions: Request body に unsupported scope / UI-only field を含めない。
- Invariants: API 日付 field は存在しないため `Date` decode は追加しない。

#### KeywordRepository

| Field | Detail |
|-------|--------|
| Intent | `/api/keywords` CRUD を mockable service boundary として提供する |
| Requirements | 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 7.1, 7.2 |

**Responsibilities & Constraints**
- APIClient を使って Bearer-authenticated `/api/keywords` request を送る。
- ViewModel が扱う `Keyword` domain value または `KeywordResponse` を返す。
- `FeedmanAPIError` を握りつぶさず、ViewModel の error mapping へ渡す。
- `URLSession` / Keychain / APNs を View へ漏らさない。

**Dependencies**
- Inbound: `KeywordSettingsViewModel` — list / mutation operations (Critical)
- Outbound: `APIClient` — request sending and 401 refresh retry (Critical)
- External: Feedman API — `/api/keywords` endpoints (Critical)

**Contracts**: Service [x] / API [x] / Event [ ] / Batch [ ] / State [ ]

##### Service Interface

```swift
protocol KeywordRepository {
    func keywords(accessToken: String) async throws -> [KeywordResponse]
    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse
    func updateKeyword(id: String, request: KeywordUpdateRequest, accessToken: String) async throws -> KeywordResponse
    func deleteKeyword(id: String, accessToken: String) async throws
}
```

- Preconditions: `accessToken` は空でない。`id` は server keyword id。create/edit term は ViewModel で trim 済み。
- Postconditions: Success 時は server-confirmed keyword state を返す。delete success 時は body を要求しない。
- Invariants: 401 refresh retry は `APIClient` の既存 hook に委譲する。

##### API Contract

| Method | Endpoint | Request | Response | Errors |
|--------|----------|---------|----------|--------|
| GET | `/api/keywords` | none | `[KeywordResponse]` または server-confirmed wrapper | 401, 429, 5xx |
| POST | `/api/keywords` | `KeywordCreateRequest` | `KeywordResponse` | 400, 409, 422, 429, 5xx |
| PATCH | `/api/keywords/{id}` | `KeywordUpdateRequest` | `KeywordResponse` | 400, 404, 409, 422, 429, 5xx |
| DELETE | `/api/keywords/{id}` | none | no content | 401, 404, 429, 5xx |

### Notifications Feature

#### KeywordSettingsViewModel

| Field | Detail |
|-------|--------|
| Intent | Keyword settings の UI state、operation guard、error mapping を調停する |
| Requirements | 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.4, 7.5 |

**Responsibilities & Constraints**
- Sheet open 時に keyword list を load し、`loading` / `empty` / `loaded` / `failed` state を公開する。
- Add/edit/toggle/delete の operation を guard し、同一操作の duplicate in-flight を防ぐ。
- Mutation success は server-confirmed state で list を更新する。
- Mutation failure は visible list を保持し、失敗した状態を confirmed として表示しない。
- Error mapping は duplicate/rate-limit/auth/network/generic を区別し、DesignSystem に API error knowledge を漏らさない。

**Dependencies**
- Inbound: `KeywordSettingsSheet` — user action and state observation (Critical)
- Outbound: `KeywordRepository` — CRUD operation (Critical)
- Outbound: `AppShell` auth guidance callback — auth-required feedback (Important)

**Contracts**: Service [x] / API [ ] / Event [ ] / Batch [ ] / State [x]

##### Service Interface

```swift
@MainActor
final class KeywordSettingsViewModel: ObservableObject {
    func loadKeywords() async
    func retryInitialLoad() async
    func createKeyword(term: String) async -> Bool
    func updateKeyword(id: String, term: String) async -> Bool
    func setKeywordEnabled(id: String, enabled: Bool) async -> Bool
    func requestDeleteConfirmation(id: String)
    func confirmDeleteKeyword() async -> Bool
}
```

- Preconditions: Mutations require authenticated access token supplied by the sheet/AppEnvironment boundary.
- Postconditions: Success state reflects server-confirmed keyword. Failure state preserves visible list.
- Invariants: Empty/whitespace term never reaches repository.

#### KeywordSettingsSheet

| Field | Detail |
|-------|--------|
| Intent | Keyword list and CRUD controls を SwiftUI sheet として表示する |
| Requirements | 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 8.1, 8.2, 8.3, 8.4 |

**Responsibilities & Constraints**
- `FeedmanSheetShell` または既存 shell pattern を使い、title、説明、list、input、mutation controls を表示する。
- Add/edit/toggle/delete controls を ViewModel action に接続する。
- Long keyword / Dynamic Type / VoiceOver で overlap を避ける。
- Token や個人情報を UI/debug log に出さない。

**Dependencies**
- Inbound: `RootView` — sheet presentation (Critical)
- Outbound: `KeywordSettingsViewModel` — state/action (Critical)
- Outbound: `FeedmanTheme`, shared primitives — visual consistency (Important)

**Contracts**: Service [ ] / API [ ] / Event [ ] / Batch [ ] / State [x]

### AppShell

#### AppShellKeywordSettingsPresentation

| Field | Detail |
|-------|--------|
| Intent | AppShell から keyword settings sheet を開き、route state を保持する |
| Requirements | 6.1, 6.2, 6.3, 6.4, 6.5, 8.5, 8.6, 8.7 |

**Responsibilities & Constraints**
- Drawer/footer に keyword settings entry point を追加する。
- Tap 時に drawer を閉じ、`AppShellPresentation.keywordSettings` をセットする。
- Sheet dismiss で current route を変えない。
- `AppEnvironment.keywordRepository` と `currentAccessToken` を sheet に渡す。
- Existing feature behavior を変更しない。

**Dependencies**
- Inbound: `DrawerView` — entry tap (Critical)
- Outbound: `KeywordSettingsSheet` — sheet content (Critical)
- Outbound: `AppEnvironment` — repository and access token (Critical)

**Contracts**: Service [ ] / API [ ] / Event [ ] / Batch [ ] / State [x]

## Data Models

### Domain Model

- Aggregate: User-owned Keyword list。Client では server user context を Bearer token に委譲し、user id は model に持たない。
- Entity: `KeywordResponse` / feature-local `KeywordRowState`。Stable identity は server `id`。
- Value objects:
  - `KeywordCreateRequest(term, scope, enabled)`
  - `KeywordUpdateRequest(term?, enabled?)`
  - `KeywordSettingsErrorPresentation(kind, title, message)`
- Domain events は導入しない。AppShell への通知は sheet dismiss / auth-required callback / toast feedback に留める。

### Logical / Physical Data Model

Client local persistence は追加しない。`hits` は server aggregate value として表示するだけで、client 側で cache や集計を持たない。

## Error Handling

### Error Strategy

- Repository は `FeedmanAPIError` を保持して throw し、ViewModel が user-facing presentation へ map する。
- Initial load failure は full sheet recoverable error + retry を表示する。
- Visible list がある状態の refresh/mutation failure は list を保持し、banner/local message で guidance を出す。
- Toggle は server confirmed 成功後に確定表示する。楽観表示を採用する場合も、失敗時 rollback を同 task のテストで固定する。
- Delete は confirmation 後に repository を呼び、成功後に list から除去する。

### Error Categories and Responses

- **User Errors (4xx)**: empty term は repository を呼ばず inline guidance。duplicate keyword は「登録済み」案内。auth-required は再ログイン guidance。
- **System Errors (5xx)**: generic recoverable error と retry guidance。visible content は破壊しない。
- **Business Logic Errors (422)**: validation / unsupported scope は入力修正 guidance。未知 code は generic recoverable に落とす。
- **Rate Limit (429)**: `FeedmanErrorContext.retryAfterSeconds` または `Retry-After` 由来値があれば待機時間を含める。

## Testing Strategy

- **Unit Tests**:
  - `KeywordResponse` / request model decode/encode が `id`, `term`, `scope`, `enabled`, `hits` と snake_case を保持する。
  - `APIClientKeywordRepository` が GET/POST/PATCH/DELETE の method/path/body/Bearer header を送る。
  - Repository が 401 refresh retry を `APIClient` に委譲する。
  - `KeywordSettingsViewModel` が load success/empty/error retry と mutation success/failure preservation を扱う。
  - Duplicate/rate-limit/auth/network error mapping が expected guidance になる。
- **Integration Tests**:
  - `AppShellState` が keyword settings presentation を持ち、dismiss 後に current route を保持する。
  - `RootView` wiring は `AppEnvironment.keywordRepository` と `currentAccessToken` を sheet に渡す境界を保つ。
  - Mock repository による list/create/update/delete が ViewModel から deterministic に検証できる。
- **E2E/UI Tests**:
  - 現時点では XCTest unit 중심。UI automation は追加しない。
  - View snapshot test は既存方針にないため必須化しない。
  - Accessibility は View code と ViewModel tests で label/state を確認し、必要なら軽量 view inspection を追加する。
- **Performance/Load**:
  - Keyword list は小規模想定。pagination は導入しない。
  - Duplicate in-flight guard により連打で同一 request が増えないことを ViewModel test で確認する。
  - Large Dynamic Type と長い keyword で layout overlap を避ける SwiftUI constraints を使う。

## Security Considerations

- Keyword terms は user content であり、tokens と一緒に log しない。
- Bearer token は `APIClient` request header だけに渡し、ViewModel / View で保持・表示しない。
- Auth-required は existing session guidance に寄せ、Notifications feature 内で refresh token や Keychain を触らない。

## Supporting References

- `design/SERVER.md` §2.3: `/api/keywords` endpoints and fields.
- `design/SPEC-iOS.md` §5.8 / §7: keyword push is next-phase and `/api/devices`, `/api/keywords` are the canonical feature endpoints.
- `docs/specs/54-apns-device-registration-foundation/requirements.md`: #54 foundation boundary and non-goals.

## Open Questions

- `GET /api/keywords` の response shape が bare array か wrapper object かは未確認。Developer は実装前に server 契約を確認し、PR の確認事項に結果を書く。
- `POST` / `PATCH` の success response が keyword item body か no-content かは未確認。設計は item body を基本とするが、server 契約が no-content なら repository で local merge せず reload を選ぶ。
- Duplicate keyword の server error `code` 名は未固定。ViewModel は `statusCode`、`code`、`category` の組み合わせで保守的に判定し、未知 code は generic recoverable にする。
