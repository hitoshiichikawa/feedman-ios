# 実装メモ

## 実装概要

- `Feedman/Core/AccountRepository.swift` を追加し、`AccountRepository` protocol と `FeedmanAccountRepository` で `GET /auth/me` を Bearer token 付き `APIClient` 経由にした。
- `AppEnvironment` に `accountRepository` と `currentAccessToken` を追加し、production の account repository は既存 `AuthRepository.refreshTokens()` を使う `APIClient` refresh hook に委譲する構成にした。
- `Feedman/Features/Account` に `AccountViewModel` / `AccountView` を追加し、sheet 表示時に current user を読み込む。状態は `idle` / `loading` / `loaded` / `failed` で表現し、retry 中の重複 request を抑止する。
- `RootView` の account presentation を placeholder から `AccountRouteView` に差し替えた。drawer は既存 `AppShellState.presentAccount()` により閉じてから sheet を出す。
- 成功時は name / email を表示し、name が空なら email、両方空なら「ログイン中のユーザー」に fallback する。email は missing / empty を許容するため `UserResponse.email` を optional にした。
- ログアウトと退会 action は表示のみ。tap 時は後続 Issue で接続する旨の alert を出すだけで、revoke / logout / delete / credential clear / session transition は実行しない。

## 変更ファイル

- `Feedman/Core/AccountRepository.swift`
- `Feedman/Core/APIModels.swift`
- `Feedman/Core/AppEnvironment.swift`
- `Feedman/Features/Account/AccountViewModel.swift`
- `Feedman/Features/Account/AccountView.swift`
- `Feedman/Features/AppShell/RootView.swift`
- `FeedmanTests/AccountRepositoryTests.swift`
- `FeedmanTests/AccountViewModelTests.swift`
- `Feedman.xcodeproj/project.pbxproj`
- `docs/specs/48-account-sheet-and-current-user-loading/impl-notes.md`

## 検証

- `plutil -lint Feedman.xcodeproj/project.pbxproj Feedman/Info.plist`
- `git diff --check`
- `swiftc -typecheck Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/AccountRepository.swift Feedman/Features/Account/AccountViewModel.swift`
- `swiftc -typecheck Feedman/Core/Models.swift Feedman/Core/APIModels.swift Feedman/Core/APIError.swift Feedman/Core/APIClient.swift Feedman/Core/Auth/TokenStore.swift Feedman/Core/Auth/AuthRepository.swift Feedman/Core/FeedRepository.swift Feedman/Core/Pagination/CursorPaginationState.swift Feedman/Core/AccountRepository.swift Feedman/Core/AppEnvironment.swift`
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 実行したが、active developer directory が `/Library/Developer/CommandLineTools` で Xcode.app ではないため失敗した。
  - エラー: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

## 確認事項

- `/auth/me` の正式な response shape は `design/SPEC-iOS.md` / `design/SERVER.md` では `id` / `name` / `email` / `avatar_url` の optionality まで明文化されていない。既存 `UserResponse` を元にしつつ、Issue #48 の fallback 要件に合わせて email missing を許容した。
- Bearer token で呼んだ `/auth/me` が Web Cookie session と完全に同じ response shape を返すかは、サーバー実装または integration test で確認が必要。
- current user の cache は入れていない。sheet が生成されるたびに `loadCurrentUser()` を実行する方針にしている。
- action tap の feedback は alert のみ。後続 Issue で logout / delete account の実挙動を接続する必要がある。
- この作業環境では Xcode.app が選択されていないため、XCTest の実行結果は未確認。Xcode 環境で指定の `xcodebuild` を再実行する必要がある。
