# 要件定義

## 概要

Issue #22 は Parent: #3 の子 Issue として、アプリ起動時に保存済み credential からセッションを復元し、login 画面と authenticated shell の分岐を一貫させる。

#19 の `TokenStore` (refresh token のみ永続)、#20 の `AuthRepository.refreshTokens()` (保存 token 不在は `missingRefreshToken`、成功時は rotation 置換保存)、#21 の `AppEnvironment.authenticationState` / `LoginRouteView` 分岐を前提とする。`design/SPEC-iOS.md` §3 のとおり access token はメモリ保持で、起動時は refresh による再発行で取得する。

なお本 Issue は watcher の promote pipeline 誤付与により自動 dispatch 不能のため、idd-claude フローを Claude Code が直接実行する (経緯は Issue コメント参照)。

## 要件

### Requirement 1: 起動時の復元試行

**Objective:** As a アプリ利用者, I want 起動時に前回のログインが自動復元される, so that 毎回 Google ログインをやり直さずに済む

#### Acceptance Criteria

1. When the app launches with a stored refresh token, the app shall refresh を試行する。
2. When the app launches without a stored refresh token, the app shall refresh request を発行せず login 画面を表示する。
3. While restoration is in progress, the app shall login 画面と authenticated shell のどちらでもない復元中表示を出し、画面の瞬間的な切り替わり (login flash) を避ける。

### Requirement 2: 復元成功

**Objective:** As a アプリ利用者, I want refresh 成功時にそのままアプリ本体へ入れる, so that 追加操作なしで利用を継続できる

#### Acceptance Criteria

1. When refresh succeeds at launch, the authenticated shell shall be shown。
2. When refresh succeeds at launch, the app shall 新しい access token をメモリ上のセッション状態として保持する (rotation 済み refresh token の保存は #20 の repository が担う)。

### Requirement 3: 復元失敗

**Objective:** As a アプリ利用者, I want 失効済みセッションが安全に破棄される, so that 不正な token が残らず明示的に再ログインできる

#### Acceptance Criteria

1. When refresh fails at launch with a stored refresh token, credentials shall be cleared and login shall be shown。
2. When the stored refresh token is missing, the app shall credential 消去を行わず (消すものがない) login を表示する。
3. The credential clearing shall ローカル消去のみとし、server への revoke request を伴わない (失効 token の revoke は server 側で拒否されるため)。

### Requirement 4: セッション状態の一貫性

**Objective:** As a 後続 Issue の実装者, I want 復元・ログイン・未認証が単一のセッション状態で表現される, so that 画面分岐や repository の token 供給が同じ source を参照できる

#### Acceptance Criteria

1. The session state shall 復元中 / 未認証 / 認証済み (access token 保持) を単一の型で表現する。
2. When restoration is attempted while the state is not restoring, the app shall 再復元を行わない (冪等)。
3. The existing login flow (#21 の `completeLogin`) shall 本変更後も authenticated 遷移として機能する。

### Requirement 5: テストカバレッジ

**Objective:** As a QA/Developer, I want 復元の成功・失敗・token 不在の分岐が単体テストで固定される, so that 起動分岐の回帰を検出できる

#### Acceptance Criteria

1. When session restore tests are run, the test suite shall mock AuthRepository のみで検証し、実ネットワーク・実 Keychain に接続しない。
2. When 復元成功 / token 不在 / refresh 失敗の各分岐が検証される, the test suite shall 最終的な authenticationState と credential 消去呼び出しの有無を検証する。
3. When 非 restoring 状態で復元が呼ばれた場合, the test suite shall 状態が変化せず refresh が試行されないことを検証する。

## 非機能要件

### NFR 1: Scope control

1. The implementation shall 起動時復元とセッション状態の表現に閉じ、アカウント削除・ログアウト UI (#49/#50)・実データ読み込みを含めない。
2. The implementation shall APIClient の 401 refresh hook (#23) への結線を行わない (実データ repository の認証結線を行う後続 Issue の責務)。
3. The implementation shall #20 の AuthRepository 契約に対し、ローカル credential 消去の境界追加のみ行い、既存メソッドの挙動を変更しない。

## スコープ外

- アカウント削除、ログアウト UI、revoke 呼び出しフロー (#49/#50)。
- 実データ (subscriptions / items) の認証付き読み込みと 401 refresh hook 結線 (#38 以降)。
- access token の有効期限監視・先回り refresh。

## 実装境界

- 変更対象: `Feedman/Core/AppEnvironment.swift` (state + 復元 API)、`Feedman/Core/Auth/AuthRepository.swift` (ローカル消去境界の追加)、`Feedman/FeedmanApp.swift` (起動 trigger)、`Feedman/Features/AppShell/RootView.swift` (復元中分岐)、`FeedmanTests` (復元テスト)。

## 確認事項

- 復元失敗時の credential 消去は `TokenStore.clearCredentials()` 相当のローカル消去とし、`AuthRepository` に `clearLocalCredentials()` を追加して境界を repository に保つ (AppEnvironment が Keychain を直接触らない)。
