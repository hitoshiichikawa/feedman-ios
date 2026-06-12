# Review Notes

<!-- idd-codex:review round=2 model=gpt-5.5 timestamp=2026-06-12T06:44:44Z -->

## Reviewed Scope

- Branch: codex/issue-21-impl-aswebauthenticationsession-login-screen
- HEAD commit: 07f094f355c5db85794c17bf45232cd7b2803d38
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 - `RootView` が未認証時に `LoginRouteView` を表示する分岐を持つ（`Feedman/Features/AppShell/RootView.swift:11`）。
- 1.2 - `LoginView` は Google login action と状態メッセージのみを表示し、fallback / account 系 action を露出していない（`Feedman/Features/Login/LoginView.swift:56`）。
- 1.3 - 初期状態は `.idle` で retry 可能としてテストされている（`FeedmanTests/LoginViewModelTests.swift:7`）。
- 1.4 - loading 中は View 側で button disabled、ViewModel 側で二重 start を guard し、重複 session が起きないことをテストしている（`Feedman/Features/Login/LoginView.swift:81`, `Feedman/Features/Login/LoginViewModel.swift:66`, `FeedmanTests/LoginViewModelTests.swift:63`）。
- 2.1 - login 開始ごとに PKCE verifier / challenge を生成する境界があり、test double で生成値が session URL に渡ることを確認している（`Feedman/Features/Login/LoginViewModel.swift:13`, `Feedman/Features/Login/LoginViewModel.swift:73`, `FeedmanTests/LoginViewModelTests.swift:14`）。
- 2.2 - `/auth/google/login` に path を正規化し、`flow=native` と `code_challenge` を設定する実装とテストがある（`Feedman/Features/Login/LoginViewModel.swift:98`, `FeedmanTests/LoginViewModelTests.swift:24`）。
- 2.3 - `callbackURLScheme` は `feedman` 固定で session starter に渡され、テストでも検証されている（`Feedman/Features/Login/LoginViewModel.swift:48`, `FeedmanTests/LoginViewModelTests.swift:25`）。
- 2.4 - login 起動境界は `ASWebAuthenticationSession` を使用しており、Login feature 内に `WKWebView` / `SFSafariViewController` 使用はない（`Feedman/Features/Login/WebAuthenticationSessionCoordinator.swift:18`）。
- 2.5 - session start 不能時は retry 可能な failed state になり、token exchange しないことをテストしている（`Feedman/Features/Login/WebAuthenticationSessionCoordinator.swift:56`, `Feedman/Features/Login/LoginViewModel.swift:91`, `FeedmanTests/LoginViewModelTests.swift:148`）。
- 3.1 - callback URL は既存の `AuthCallbackParser` 境界で `auth_code` 抽出される（`Feedman/Features/Login/LoginViewModel.swift:83`）。
- 3.2 - valid callback 後に `AuthRepository.exchangeAuthCode(_:codeVerifier:)` へ auth code と対応 verifier を渡す実装とテストがある（`Feedman/Features/Login/LoginViewModel.swift:83`, `FeedmanTests/LoginViewModelTests.swift:36`）。
- 3.3 - token exchange 成功時に `.authenticated` へ遷移し、`AppEnvironment` の認証状態更新へ handoff する（`Feedman/Features/Login/LoginViewModel.swift:89`, `Feedman/Core/AppEnvironment.swift:38`, `FeedmanTests/LoginViewModelTests.swift:56`）。
- 3.4 - 成功 callback 内で即時に `onAuthenticated` を呼ぶため、追加 tap なしに root の authenticated shell 分岐へ移る（`Feedman/Features/Login/LoginViewModel.swift:90`, `Feedman/Features/AppShell/RootView.swift:13`）。
- 3.5 - callback parse error は token exchange せず failed state になることをテストしている（`FeedmanTests/LoginViewModelTests.swift:106`）。
- 3.6 - token exchange error は failed state になり retry 可能であることをテストしている（`FeedmanTests/LoginViewModelTests.swift:126`）。
- 3.7 - in-flight PKCE verifier は `defer` で完了 / 失敗時に破棄される（`Feedman/Features/Login/LoginViewModel.swift:75`）。
- 4.1 - cancellation は `.canceled` に留まり、authenticated handoff を呼ばない経路としてテストされている（`Feedman/Features/Login/LoginViewModel.swift:91`, `FeedmanTests/LoginViewModelTests.swift:86`）。
- 4.2 - cancellation 後に loading が解除され retry 可能であることをテストしている（`FeedmanTests/LoginViewModelTests.swift:101`）。
- 4.3 - cancellation 時に token exchange が呼ばれないことをテストしている（`FeedmanTests/LoginViewModelTests.swift:101`）。
- 4.4 - cancellation は repository 境界へ到達しないため、refresh token credential の永続化・変更も発生しない（`Feedman/Features/Login/LoginViewModel.swift:79`, `FeedmanTests/LoginViewModelTests.swift:101`）。
- 5.1 - login success を `AppEnvironment.authenticationState` として root が observe 可能にしている（`Feedman/Core/AppEnvironment.swift:24`, `Feedman/Core/AppEnvironment.swift:38`）。
- 5.2 - authenticated state では login screen ではなく `authenticatedShell` を primary route に表示する（`Feedman/Features/AppShell/RootView.swift:13`）。
- 5.3 - login screen は API feature loading を持たず、authenticated shell 側の責務に分離されている（`Feedman/Features/Login/LoginView.swift:27`, `Feedman/Features/AppShell/RootView.swift:26`）。
- 5.4 - Stage A の handoff は minimal な `AppAuthenticationState.authenticated(accessToken:)` に留まっている（`Feedman/Core/AppEnvironment.swift:4`, `Feedman/Core/AppEnvironment.swift:38`）。

## Findings

なし

## Summary

round=2 の独立レビューとして `AGENTS.md`、`requirements.md`、`impl-notes.md`、既存 `review-notes.md`、`.codex/agents/reviewer.md`、および `develop..HEAD` の差分を確認した。指定された `tasks.md` と任意の `design.md` は存在しなかった。

前回指摘の login URL path 正規化と session start 失敗時テストは HEAD commit で対応済み。`plutil -lint Feedman.xcodeproj/project.pbxproj Feedman/Info.plist` は成功し、`xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は Xcode 未選択のため実行不能だったが、reject 対象の AC 未カバー / missing test / boundary 逸脱は見つからなかった。

RESULT: approve
