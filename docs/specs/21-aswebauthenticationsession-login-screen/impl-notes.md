# 実装ノート

## 実装概要

- SwiftUI のログイン画面を `Feedman/Features/Login` に追加し、未認証時に Google ログイン action だけを表示するようにした。
- `LoginViewModel` で Google ログイン開始時に PKCE verifier/challenge を生成し、`/auth/google/login?flow=native&code_challenge=...` を `ASWebAuthenticationSession` 起動境界へ渡すようにした。
- `ASWebAuthenticationSession` の `callbackURLScheme` は `feedman` とし、callback URL は既存の `AuthCallbackParser` で `auth_code` を抽出するようにした。
- token exchange は既存の `AuthRepository.exchangeAuthCode(_:codeVerifier:)` に委譲し、成功時は `AppEnvironment` の認証状態を authenticated に切り替えて既存 app shell を表示するようにした。
- キャンセル、callback parse error、token exchange failure ではログイン画面に留まり、再試行可能な state に戻すようにした。
- 二重 tap 中は `loading` state で重複 session を開始しないようにした。
- `feedman` custom URL scheme を `Info.plist` に登録した。

## 変更ファイル

- `Feedman/Features/Login/LoginView.swift`
- `Feedman/Features/Login/LoginViewModel.swift`
- `Feedman/Features/Login/WebAuthenticationSessionCoordinator.swift`
- `Feedman/Core/AppEnvironment.swift`
- `Feedman/Features/AppShell/RootView.swift`
- `Feedman/FeedmanApp.swift`
- `Feedman/Info.plist`
- `FeedmanTests/LoginViewModelTests.swift`
- `Feedman.xcodeproj/project.pbxproj`

## テスト

- `plutil -lint Feedman.xcodeproj/project.pbxproj Feedman/Info.plist`
  - 結果: 成功。
- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 結果: 失敗。
  - 理由: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

## 確認事項

- 本番 API / auth base URL の正式値は未確認。Stage A では `AppEnvironment.production()` の default を `http://localhost:3000` としている。
