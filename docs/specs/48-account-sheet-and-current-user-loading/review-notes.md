# Review Notes: Issue #48 Account sheet and current user loading

## Summary

round=1 / 最大2 round の独立レビューを実施した。

必読指定のうち `AGENTS.md`、`requirements.md`、`impl-notes.md` は確認済み。`tasks.md` と `design.md` は `docs/specs/48-account-sheet-and-current-user-loading/` 配下に存在しなかったため、tasks 由来の `_Requirements:_` / `_Boundary:_` は確認できなかった。差分は `git diff --stat develop..HEAD` と `git log --oneline develop..HEAD` で取得でき、実装 commit は `a60a622 feat: add account current user sheet` だった。

判定カテゴリを `AC 未カバー` / `missing test` / `boundary 逸脱` に限定して確認した結果、reject 相当の指摘はない。

## Findings

なし。

## AC Coverage

- Requirement 1: `RootView` の sheet 接続で account presentation が `AccountRouteView` に差し替えられ、drawer からの起動時は `AppShellState.presentAccount()` が drawer を閉じて sheet を出すため、presentation state の重複は避けられている（`Feedman/Features/AppShell/RootView.swift:99`, `Feedman/Features/AppShell/RootView.swift:210`, `Feedman/Features/AppShell/AppShellState.swift:141`）。sheet は `FeedmanSheetShell` の日本語 title / close affordance を使っている（`Feedman/Features/Account/AccountView.swift:39`）。
- Requirement 2: sheet 表示時に `.task` から current user loading を開始し、repository が `GET /auth/me` を Bearer token 付き `APIClient` に委譲している（`Feedman/Features/Account/AccountView.swift:26`, `Feedman/Core/AccountRepository.swift:10`）。refresh は `AppEnvironment.production` の `APIClient` refresh hook に委譲され、Account feature 側に独自 refresh 実装はない（`Feedman/Core/AppEnvironment.swift:62`）。
- Requirement 3: `AccountDisplayUser` が name/email の trim と fallback を行い、UI は name/email を折り返し可能な Text として表示する（`Feedman/Features/Account/AccountViewModel.swift:10`, `Feedman/Features/Account/AccountView.swift:109`）。
- Requirement 4: loading / failed / retry の状態が ViewModel と UI にあり、retry は同じ loading 経路を再実行し、loading 中の重複 request は ViewModel 側で抑止されている（`Feedman/Features/Account/AccountViewModel.swift:67`, `Feedman/Features/Account/AccountView.swift:69`）。typed Feedman error / auth loss も日本語表示へ mapping されている（`Feedman/Features/Account/AccountViewModel.swift:110`）。
- Requirement 5: loaded state のみ logout / delete account actions を表示し、tap は alert 表示に留まり、logout/revoke/delete/credential clear/session transition は呼んでいない（`Feedman/Features/Account/AccountView.swift:87`, `Feedman/Features/Account/AccountView.swift:139`, `Feedman/Features/Account/AccountViewModel.swift:96`）。
- Requirement 6: `AccountRepository` protocol と real implementation が追加され、ViewModel は repository protocol 経由で current user を取得し、`@MainActor` で UI state を更新している（`Feedman/Core/AccountRepository.swift:3`, `Feedman/Features/Account/AccountViewModel.swift:54`）。`UserResponse` は `Codable` の API model として `id` / `email` / `name` / `avatar_url` を扱っている（`Feedman/Core/APIModels.swift:211`）。

## Test Coverage

- `AccountRepositoryTests` は `/auth/me` の GET、Authorization header、body なし、401 refresh retry hook 委譲、`UserResponse` decode を検証している（`FeedmanTests/AccountRepositoryTests.swift:7`, `FeedmanTests/AccountRepositoryTests.swift:27`, `FeedmanTests/AccountRepositoryTests.swift:57`）。
- `AccountViewModelTests` は loading -> success、認証 token 欠落、failure、retry、loading 中の重複 request 抑止、name/email fallback、placeholder action が repository/API を呼ばないことを検証している（`FeedmanTests/AccountViewModelTests.swift:6`, `FeedmanTests/AccountViewModelTests.swift:30`, `FeedmanTests/AccountViewModelTests.swift:48`, `FeedmanTests/AccountViewModelTests.swift:68`, `FeedmanTests/AccountViewModelTests.swift:85`, `FeedmanTests/AccountViewModelTests.swift:101`, `FeedmanTests/AccountViewModelTests.swift:115`）。
- `impl-notes.md` によると指定の `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test` は active developer directory が CommandLineTools のため失敗している。本レビューでは追加の build/test 実行はしていない。

## Boundary Check

- View は `URLSession` / Keychain / raw token store を直接触らず、`AccountRepository` と `AppEnvironment.currentAccessToken` を通している。
- logout / delete account の実挙動、`POST /api/auth/revoke`、`POST /auth/logout`、`DELETE /api/users/me`、credential clear、login transition は追加されていない。
- v1 スコープ外の keyword notification、OPML、profile editing、multi-account switching、WebView Cookie login fallback は追加されていない。
- `docs/specs/48-account-sheet-and-current-user-loading/requirements.md` と `impl-notes.md` が差分に含まれているが、今回の review 作業では既存実装・仕様ファイルは変更していない。

RESULT: approve
