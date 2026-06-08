# Feedman iOS アプリ 開発仕様書

> **対象読者**: Codex（コーディングエージェント）および実装担当者
> **バージョン**: v1.0 / 2026-06-08
> **入力成果物**: `Feedman iPhone.html`（iOS プロトタイプ）, `Feedman Mobile.html`（Android 版・参考）
> **既存システム**: `feedman/`（Go バックエンド + Next.js Web フロント、単一オリジン構成）
> **対になる文書**: `SPEC.md`（Android 版）, `SERVER.md`（サーバー追加実装）

このドキュメント単体で iOS 実装に着手できることを目標とする。**API リファレンス（§4）・画面の採用案（§5）・共通挙動（§6）・新規 API（§7）・受け入れ基準（§10）は Android 版（`SPEC.md`）と完全に同一**であり、本書ではプラットフォーム固有差分（§2 技術 / §3 認証 / §8 デザイン / §9 プロト / §11 iOS 作法）を iOS 向けに記述する。

---

## 0. このドキュメントとプロトタイプを Codex にそのまま渡してよいか

**結論: プロトタイプ単体では不十分。本書と併せて渡すこと。**

| 成果物 | 信用してよい範囲 | 信用してはいけない範囲 |
|---|---|---|
| 本仕様書（.md） | API 契約・画面挙動・受け入れ基準・採用案 | — |
| プロトタイプ（.html） | 画面レイアウト・インタラクション・状態遷移・配色/タイポ | **データはすべてモック**。API 形・ページネーション・エラーは未反映。React Web であり SwiftUI ネイティブ実装ではない |

Codex への推奨インプット順:
1. 本書（`SPEC-iOS.md`）
2. プロトタイプ `Feedman iPhone.html`（「この見た目・挙動を SwiftUI で再現せよ」の視覚基準として）
3. `SERVER.md`（トークン認証・プッシュのサーバー契約）
4. 既存リポジトリ `feedman/`（API 実装の最終的な真実）

> **重要**: プロトタイプの Tweaks（複数案の出し分け）は**探索用**。実装では §5 の「採用案」を唯一の正とすること。

---

## 1. 概要

Feedman は RSS/Atom フィードリーダー。Google OAuth、フィード横断の新着タイムライン、はてなブックマーク連携を持つ。本プロジェクトは既存 Web の **API をほぼそのまま流用**して iOS ネイティブアプリを新規開発する。Android 版と**同一の機能・API・採用案**で、iOS の作法に合わせて実装する。

### 1.1 想定ユーザー / 主要ユースケース
- 通勤中のニュースチェック。複数フィードの新着を 1 タイムラインで消化。
- 気になる記事は **SFSafariViewController** で本文を読む。
- **キーワードを登録しておき、一致する新着タイトルが来たらプッシュ通知**（→ サーバー新設・次フェーズ。§7）。

### 1.2 v1 スコープ
すべての新着（横断タイムライン）／フィード別記事一覧／記事詳細閲覧／スター一覧／横断検索／フィード登録／購読設定（間隔・解除・再開）／Google ログイン（トークン認証）／アカウント（ログアウト・退会）。
（キーワードプッシュ通知は次フェーズ。§1.3 / §7 参照）

### 1.3 スコープ外（v1 では作らない）
- **キーワードプッシュ通知 → 次フェーズ**（サーバー側も次バージョンで対応。UI も次フェーズに送る。§7 参照）。
- フィード内検索 UI（API はあるが横断検索に集約）、フィード URL 変更 UI、OPML 入出力、オフライン全文キャッシュ。

---

## 2. 技術前提（確定）

> **確定済み（2026-06-08）**。以下のスタックで実装する。Android 版（Kotlin/Compose）と機能等価。

| 項目 | 選定 | 備考 |
|---|---|---|
| 言語 / UI | **Swift + SwiftUI** | プロトタイプの宣言的構造と相性が良い |
| 最低 OS | **iOS 16** | `NavigationStack` / `.presentationDetents`（ボトムシート）の前提を満たす |
| アーキテクチャ | MVVM + Repository、`@Observable` / `ObservableObject` による単方向データフロー | プロトの `actions`/`state` 分離に対応 |
| 非同期 / ページング | **async/await + Swift Concurrency**。無限スクロールは `.onAppear` センチネル + カーソル保持 | カーソルページネーション（§4.1）。Paging 相当を自前 Repository で実装 |
| ネットワーク | **URLSession + Codable**（`async` API）。薄い `APIClient` ラッパ | Android の Retrofit 相当 |
| 画像 | **AsyncImage**（or Nuke）。data URL は §4.4 注意 | favicon は data URL |
| 外部リンク | **SFSafariViewController**（`SafariServices`） | アプリ内 Safari。Cookie/リーダー対応。完全外部 `UIApplication.open` 切替も設定で可能に |
| プッシュ | **APNs**（サーバーは FCM 経由で APNs 配信） | §7 のサーバー新設が前提・次フェーズ |
| トークン保管 | **Keychain**（`kSecClassGenericPassword`、`accessibility=afterFirstUnlock`） | Android Keystore 相当 |
| DI | イニシャライザ注入 + 環境オブジェクト（`@Environment`） | 軽量に保つ |

---

## 3. 認証（最重要の設計判断）

既存 Web は **Cookie セッション（`SameSite=Lax`）+ CORS 制限 + 同一オリジン相対パス**で動作する。ネイティブアプリはオリジンを持たないため、この方式をそのまま使うと OAuth リダイレクトと Cookie 共有で破綻する。**ここが「流用が苦しい」唯一の中核。**

### 3.1 既存の認証フロー（Web）
- `GET /auth/google/login` → Google 認可画面へリダイレクト
- `GET /auth/google/callback` → セッション Cookie を発行し、フロントのオリジンへリダイレクト
- `POST /auth/logout` / `GET /auth/me`（現在ユーザー）
- 以降の API は Cookie を自動送信

> **確定（2026-06-08）: 方針 A（トークン認証）を v1 から採用。** サーバー側のトークン発行・検証エンドポイントを v1 のうちに新設する（`SERVER.md` §1）。

### 3.2 方針 A（採用・サーバー新設）— トークン認証
OAuth 完了後に**短命アクセストークン + リフレッシュトークン**を発行する。

```
POST /api/auth/token        # OAuth 完了一時コード + PKCE verifier → { access_token, refresh_token, expires_in }
POST /api/auth/refresh      # { refresh_token } → 新しい access_token（ローテーション）
POST /api/auth/revoke       # { refresh_token } → ログアウト時に失効
```

iOS 実装の要点:
- **`ASWebAuthenticationSession`** で `GET /auth/google/login?flow=native&code_challenge=...` を開く（アプリ内ブラウザでの OAuth に最適。Cookie 分離・自動クローズ対応）。
- コールバックは **ユニバーサルリンク or カスタムスキーム** `feedman://auth/callback?auth_code=...` で受領（`ASWebAuthenticationSession` の `callbackURLScheme` に `feedman` を指定）。
- 受け取った `auth_code` を `POST /api/auth/token`（PKCE `code_verifier` 同送）で本トークンへ交換。
- アクセストークンは全 API に `Authorization: Bearer <access_token>` を付与。401 を検知したら `refresh` → リトライを `APIClient` で透過処理。
- トークンは **Keychain** に保管（`refresh_token` のみ永続。`access_token` はメモリ + 短命）。
- **PKCE 必須**（S256）。`code_verifier` は交換まで保持。

> **Codex への指示**: 認証層は `AuthRepository`（protocol）で抽象化し、`TokenStore`（Keychain）と `APIClient`（自動リフレッシュ）を分離する。トークンのライフサイクル・ローテーション・再利用検知のサーバー仕様は `SERVER.md` §1 を参照。

### 3.3 方針 B（不採用・参考）
新設なしで `WKWebView` ログイン + Cookie（`HTTPCookieStorage` 共有）を流用する代替案だったが、方針 A 採用のため**実装しない**。`AuthRepository` 抽象化の設計参考としてのみ記す。

---

## 4. API リファレンス（実装に対する正本）

**Android 版 `SPEC.md` §4 と完全に同一。** ここでは iOS 実装の型変換の注意のみ補足し、全文は `SPEC.md` §4 を正とする（重複を避けるため要点を再掲）。

- すべて JSON。認証必須エンドポイントは §3 の Bearer トークンを付与。
- ベースパス: 既存と同じ。アプリでは `baseURL` を環境（Debug/Release）で切替。
- **ページネーション（カーソル方式）**: `{ items, next_cursor: string?, has_more }`。次ページは `?cursor=<next_cursor>&limit=<n>`。`has_more==false` か `next_cursor` が null/空で終端。横断新着のみ `since_time`（RFC3339）を返し、**セッション初回値を固定**。
- **エラー**: `{ error: { code, message, category, action, details? } }`。`429 / FEED_COOLDOWN` は `details.retry_after_seconds` と `Retry-After` ヘッダ。

### 4.2 エンドポイント一覧（再掲・正本は SPEC.md §4.2）

| 区分 | メソッド | パス |
|---|---|---|
| 認証/ユーザー | GET | `/auth/google/login`（`flow=native` で iOS 用コールバック） |
| | GET | `/auth/google/callback` |
| | POST | `/auth/logout` |
| | GET | `/auth/me` |
| | DELETE | `/api/users/me`（退会） |
| | PUT | `/api/users/me/cross-feed-last-seen` |
| 横断新着 | GET | `/api/items/cross-feed`（50件/回・上限200・`since_time`付） |
| 購読 | GET | `/api/subscriptions` |
| | DELETE | `/api/subscriptions/{id}`（解除） |
| | PUT | `/api/subscriptions/{id}/settings`（間隔等） |
| | POST | `/api/subscriptions/{id}/resume`（再開） |
| | POST | `/api/subscriptions/{id}/fetch`（手動フェッチ=Pull-to-refresh） |
| フィード | POST | `/api/feeds`（登録・URL自動検出） |
| | GET | `/api/feeds/{id}/items?filter=all\|unread\|starred` |
| | GET | `/api/feeds/starred/items` |
| 記事 | GET | `/api/items/{id}`（`content`含む） |
| | PUT | `/api/items/{id}/state`（`{is_read?, is_starred?}`） |
| 検索 | GET | `/api/items/search?q=&scope=global\|feed` |

### 4.3 Codable 型（iOS）
TypeScript 型（`SPEC.md` §4）をそのまま `Codable` に写す。注意点:
- `feed_favicon_url` / `favicon_url` は **`String?`**（null あり）。
- `ItemSearchHit` は `published_at: String?`、`favicon_url: String?` を持ち、**`hatebu_fetched_at` を含まない**（`ItemSummary` と別 struct にする）。
- 日付は `String`（RFC3339）で受けて表示時に整形（§6）。`Date` への自動デコードに頼らない（`is_date_estimated` 等のため）。
- スネークケースは `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` か `CodingKeys` で対応。

### 4.4 favicon の扱い（注意）
`feed_favicon_url` / `favicon_url` は **`data:<mime>;base64,...` 形式の data URL** か `null`。
- `AsyncImage(url:)` は `data:` URL を読めないため、**`data:` を検出したら `Data(base64:)` でデコードして `UIImage` 化**するカスタムビューを用意する。`null`/失敗時は色付きレターアバター（プロトの `FMFavicon` 参照）にフォールバック。

---

## 5. 画面仕様（採用案を固定）

**Android 版 `SPEC.md` §5 と採用案は同一。** iOS のコンポーネント対応を併記する。実装は採用案のみ。

### 5.0 ナビゲーション構造 — 採用: **左ドロワー + 記事ビュー**（Tweak `nav=drawer`）
- iOS には標準ドロワーが無いため、**カスタムサイドメニュー**で実装（メインを右へオフセット + スクリム + ドラッグ/スワイプで開閉）。トップバーは `.toolbar`：左にハンバーガー、中央にタイトル、右に検索・テーマ切替。
- ドロワー内: ヘッダ（ロゴ + ユーザー）／「すべての新着」「お気に入り」／フィード一覧（未読バッジ・状態アイコン・設定）／フッタ（アカウント・テーマ）。※「キーワード通知」導線は v1 非表示（次フェーズ）。
- 代替（不採用）: 下タブ（`TabView`）。比較したい場合のみプロト `nav=bottomtabs`。

### 5.1 新着横断タイムライン — 採用: **カード**（Tweak `timeline=cards`）
- データ: `GET /api/items/cross-feed`（`since_time` 固定、無限スクロール）。
- カード: フィード名 + favicon、相対日時、タイトル（最大3行）、概要（最大2行）、はてブ数、スター、**外部リンクアイコン**。
- 既読記事は不透明度を下げる（opacity 0.55）。
- タップ = 記事詳細シート（§5.4）。外部リンクアイコンタップ = SFSafariViewController で `link` を開く + 既読化。
- Pull-to-refresh: 横断は `.refreshable` で GET 再取得（§4 / §11）。

### 5.2 フィード別記事一覧 — 採用カード: **標準**（Tweak `card=standard`）
- データ: `GET /api/feeds/{id}/items?filter=...`。上部にフィルタ（すべて/未読/スター。`Picker` セグメント or カスタムチップ）→ `filter` クエリ。
- フィード状態が `stopped`/`error` のとき上部に警告バナー + 「再開」（`POST .../resume`）。
- Pull-to-refresh = `.refreshable` → `POST /api/subscriptions/{id}/fetch`（クールダウン 429 をトースト/バナーで案内）。

### 5.3 スター一覧 / 検索
- スター: `GET /api/feeds/starred/items`（`feed_title` でソース表示）。
- 検索: `GET /api/items/search?q=`（`.searchable` か自前検索バー）。空状態でサジェストチップ。結果は `ItemSearchHit`。

### 5.4 記事詳細 — 採用: **部分シート（プレビュー）**（Tweak `detail=partial`）
- **`.sheet` + `.presentationDetents([.medium, .large])`** で実装（medium がプレビュー、ドラッグで large 展開＝「続きを読む」相当）。
- ソース行・タイトル・はてブ/スター・本文プレビュー（`content` を HTML→`AttributedString` or 簡易レンダ）。
- フッタ固定アクション: **「元記事を開く」（主ボタン → SFSafariViewController）** + スター。
- 開いた時点で既読化（`PUT /api/items/{id}/state {is_read:true}`）。
- 代替（不採用）: 全画面シート（`.large` 固定）/ リーダー。

### 5.5 フィード登録
- `POST /api/feeds`。URL 入力 → 検出 → 確認 → 登録。専用レート制限と重複登録エラーをハンドリング。`.sheet` で表示。

### 5.6 購読設定（ボトムシート）
- `.sheet` + `.presentationDetents`。フェッチ間隔セグメント（15/30/60/180/360分）→ `PUT /api/subscriptions/{id}/settings`。
- 再開（`POST .../resume`）、購読解除（`DELETE /api/subscriptions/{id}`、確認 `.alert` 付き）。

### 5.7 ログイン / アカウント
- ログイン: §3 のフロー（`ASWebAuthenticationSession`）。Google ボタン1つ。
- アカウント: `GET /auth/me` 表示、ログアウト（`revoke` + `POST /auth/logout`）、退会（`DELETE /api/users/me`、二段確認）。

### 5.8 キーワードプッシュ通知設定 — **次フェーズ（v1 スコープ外）**
- サーバー新設とセットで次バージョン対応。プロトに UI 案はあるが **v1 では実装しない**（ドロワーの導線も非表示）。詳細は §7 / `SERVER.md` §2。

---

## 6. 共通の挙動・状態

- **既読化のタイミング**: 詳細シートを開いた時・外部リンクを開いた時に `is_read:true`。一覧へ即時反映（楽観的更新 → 失敗時ロールバック）。
- **スター**: 一覧/詳細どこからでもトグル。楽観的更新。
- **テーマ**: ライト/ダーク切替（`.preferredColorScheme` で端末追従 + 手動上書き）。トークンは §8。
- **無限スクロール**: 全一覧で末尾センチネル + カーソル継ぎ足し。終端表示「最後まで読みました」。
- **空状態 / エラー / ローディング**: 各一覧で用意（プロトの `FMEmpty` 参照。`ContentUnavailableView` 活用可）。
- **相対日時**: 「1時間以内 / N時間前 / N日前 / 日付」。`is_date_estimated` のとき「(推定)」表示。

---

## 7. 新規 API（サーバー追加が必要）

**Android 版と同一。** 詳細は `SERVER.md`。

| 優先 | 機能 | エンドポイント | フェーズ |
|---|---|---|---|
| ★★★ | トークン認証 | `POST /api/auth/token`, `/refresh`, `/revoke` | **v1**（採用済・§3） |
| ★★★ | キーワードプッシュ | `/api/devices`, `/api/keywords`（`SERVER.md` §2） | **次フェーズ** |
| ★★ | 一括既読 | `PUT /api/feeds/{id}/read-all` ほか | 次フェーズ候補 |
| ★ | 起動同期 | `GET /api/sync?since=` | 次フェーズ候補 |

> **iOS 固有**: プッシュは APNs。端末登録は `POST /api/devices { platform:"ios", push_token }`（`push_token` は APNs デバイストークン。サーバーは FCM 経由で APNs 配信）。通知タップで `feedman://items/{id}` ディープリンク → 記事詳細。`UNUserNotificationCenter` で許可要求・受信処理。v1 では実装しない。

---

## 8. デザイントークン

プロトタイプ `mobile/fm-data.jsx` の `FM_THEME` が正本。要点:
- **配色**: oklch グレースケール（Web の `globals.css` を移植）。ライト/ダーク両対応。SwiftUI では `Color` を P3/sRGB で近似定義（プロトの oklch 値を変換した固定 hex/RGB をトークン化）。
- **アクセント**: 1色（**Indigo `oklch(0.55 0.17 264)` ≒ sRGB `#4F46E5` 近傍に確定**）。Coral/Teal/Violet は不採用。
- **角丸**: 10–16px。**タイポ**: Geist（同梱フォント or San Francisco で近似）。Dynamic Type 対応を推奨。
- **タップ標的**: 最小 44pt（iOS HIG）。アイコン 18–22pt。
- **セーフエリア**: ステータスバー/Dynamic Island・ホームインジケータを尊重（プロトでも上 56 / 下 22 相当を確保。実機は `safeAreaInsets` を使用）。

---

## 9. プロトタイプの読み方（Codex 向け）

- `Feedman iPhone.html` … iOS 版。**画面・挙動の視覚基準**。
- `Feedman Mobile.html` … Android 版（参考）。
- `mobile/fm-data.jsx` … トークン・アイコン・**モックデータ形**（実 API 形は §4 が正）。
- `mobile/fm-ui.jsx` … カード/スター/はてブ/Pull-to-refresh 等の共通部品。
- `mobile/fm-screens.jsx` … ヘッダ・ドロワー・各画面。
- `mobile/fm-sheets.jsx` … 詳細・登録・設定・ログインの各シート。

**やってよいこと**: レイアウト・余白・状態遷移・空/エラー表示・配色をピクセル単位で参照。
**やってはいけないこと**: モックの JSON 形をそのまま API 型と見なす（§4 を優先）。Tweaks の複数案を実装する（§5 の採用案のみ）。React/HTML をそのまま移植しようとする（**SwiftUI で再構築**する）。

---

## 10. 受け入れ基準（v1 / 抜粋）

- [ ] Google ログイン（`ASWebAuthenticationSession` → token 交換）→ 横断タイムライン表示まで到達できる。
- [ ] 横断タイムラインが無限スクロールし、`since_time` がセッション中固定される。
- [ ] フィード別一覧でフィルタ（すべて/未読/スター）が `filter` クエリで切り替わる。
- [ ] 記事タップで `.medium` ディテントのシートが開き、開いた時点で既読になる（楽観的更新 + サーバー反映）。
- [ ] 「元記事を開く」で SFSafariViewController が起動し、当該記事が既読化される。
- [ ] スターのトグルが一覧/詳細/スター一覧で整合する。
- [ ] フィード別 Pull-to-refresh（`.refreshable`）が `POST .../fetch` を呼び、`FEED_COOLDOWN` 時に `retry_after_seconds` を案内する。
- [ ] フィード登録・購読解除・間隔変更・再開が各エンドポイントで成功する。
- [ ] 401 で自動リフレッシュ → リトライが透過的に動作する。
- [ ] ライト/ダーク切替が全画面に反映される。
- [ ] （次フェーズ / §7 実装後）キーワード登録 → 一致記事の APNs プッシュ受信 → タップで詳細へ遷移。

---

## 11. iOS 作法の要点（Android との差分まとめ）

| 観点 | Android（SPEC.md） | iOS（本書） |
|---|---|---|
| UI フレームワーク | Jetpack Compose | SwiftUI |
| 外部リンク | Chrome Custom Tabs | SFSafariViewController |
| ボトムシート | Material BottomSheet | `.sheet` + `.presentationDetents` |
| ドロワー | Navigation Drawer（標準） | カスタムサイドメニュー（標準なし） |
| Pull-to-refresh | SwipeRefresh | `.refreshable` |
| OAuth | Custom Tabs + App Links | `ASWebAuthenticationSession` |
| トークン保管 | Keystore + EncryptedSharedPreferences | Keychain |
| プッシュ | FCM | APNs（サーバーは FCM→APNs） |
| 最小バージョン | API 26 | iOS 16 |
| ページング | Paging 3 | 自前カーソル + センチネル |

---

## 付録 A. 決定事項（2026-06-08 確定済み）
1. ✅ 技術スタック: **Swift + SwiftUI / iOS 16+**（§2）。
2. ✅ 認証方針: **A（トークン認証）を v1 から**（`ASWebAuthenticationSession` + PKCE + Keychain）。
3. ✅ アクセントカラー: **Indigo**（sRGB `#4F46E5` 近傍）。
4. ✅ キーワードプッシュ: **次フェーズ**（サーバー・アプリとも v1 スコープ外。iOS は APNs）。
5. ✅ 横断 Pull-to-refresh: **GET 再取得のみ**（一括同期 API は設けない）。

→ API・画面・挙動の正本は `SPEC.md`（Android）と共通。本書は iOS 固有差分を定義する。Codex へは本書（SPEC-iOS.md）+ `Feedman iPhone.html` + `SERVER.md` を渡してよい。
