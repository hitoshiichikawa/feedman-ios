# Issue #50 Account deletion confirmation flow 実装ノート

## 実装概要

- `AccountRepository` に `deleteCurrentUser(accessToken:)` を追加し、real implementation で `DELETE /api/users/me` を Bearer token 付きで呼ぶようにした。
- `APIClient` に body なしの `sendNoContent` overload を追加し、DELETE request が body を持たない形で送れるようにした。
- `AccountViewModel` に退会専用の `AccountDeletionState` を追加し、`idle` / `confirming` / `deleting` / `failed` / `succeeded` を明示した。
- `AccountView` の退会 button から SwiftUI `.alert` の destructive confirmation を表示し、確認後に ViewModel 経由で退会 API を実行するようにした。
- 退会成功後は `AppEnvironment.clearLocalAuthenticationAfterAccountDeletion()` により `AuthRepository.clearLocalCredentials()` を使って local credentials を消去し、in-memory access token と `authenticationState` を unauthenticated へ遷移させるようにした。
- 退会失敗時は local credentials と authenticated session state を変更せず、Account sheet 内に日本語の error state と再試行導線を表示するようにした。

## テスト

- `AccountViewModelTests` に confirmation 表示、cancel 時 no request、success 時 session clear completion、failure 時 session preserve、duplicate request prevention を追加した。
- `AccountRepositoryTests` に `DELETE /api/users/me` の method / path / Bearer / no body と、任意の 2xx body を success と扱う検証を追加した。
- `AppEnvironmentSessionRestoreTests` に退会成功後の local credential clear と unauthenticated transition、および revoke API を呼ばないことの検証を追加した。

## 検証結果

- `xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test`
  - 実行不可。`DEVELOPER_DIR` 未指定では active developer directory が CommandLineTools のため `xcodebuild` が起動できなかった。
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 指定後も、この環境には `iPhone 16` Simulator が存在せず destination 解決に失敗した。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - 成功。236 tests, 0 failures。

## 確認事項

- 退会成功 response は `APIClient.validateNoContent` の契約に合わせ、204 No Content だけでなく任意の 2xx response を成功として扱っている。
- 退会成功後の local credential clear は既存の起動時復元 failure path と同様に、Keychain clear error を UI 上の退会失敗には戻さず、in-memory session を unauthenticated に遷移させる実装にしている。
- ログアウト flow は既存 placeholder のまま維持し、Issue #50 の退会 flow とは混同していない。
