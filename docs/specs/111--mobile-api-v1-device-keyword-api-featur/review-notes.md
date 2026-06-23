# Review Notes

<!-- idd-codex:review round=1 model=gpt-5.5 timestamp=2026-06-23T13:30:22Z -->

## Reviewed Scope

- Branch: codex/issue-111-impl--mobile-api-v1-device-keyword-api-featur
- HEAD commit: e32809f59e7449937d869f14a777125309378809
- Compared to: develop..HEAD

## Verified Requirements

- 1.1 — `AppEnvironment.production(notificationFeatures:)` の default が `.v1Default` で、`NotificationFeatureFlags.v1Default.keywordNotificationsEnabled == false`。`testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` で検証。
- 1.2 — production default の `deviceRegistrationRepository` は `APIClientDeviceRegistrationRepository` ではない。`testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` で検証。
- 1.3 — production default の `keywordRepository` は `DisabledKeywordRepository`。`testProductionEnvironmentUsesV1DefaultDisabledNotificationDependencies` と disabled repository tests で検証。
- 1.4 — `.nextPhaseEnabled` 明示時は `APIClientKeywordRepository` / `APIClientDeviceRegistrationRepository` を使える。`testProductionEnvironmentCanEnableNotificationDependenciesExplicitly` で検証。
- 1.5 — `NotificationFeatureFlags` は `AppEnvironment.production(notificationFeatures:)` に注入可能で、remote config / server dependency は追加されていない。
- 2.1 — `DrawerView` は `showsKeywordSettingsAction` が false のとき「キーワード通知」を描画しない。`testDisabledKeywordSettingsRouteGateHidesEntryAndIgnoresPresentationRequest` で gate を検証。
- 2.2 — disabled 時の `presentKeywordSettings(on:)` は presentation を作らない。`testDisabledKeywordSettingsRouteGateHidesEntryAndIgnoresPresentationRequest` で検証。
- 2.3 — `visiblePresentation(from:)` と `sheetContent(.keywordSettings)` が disabled 時の sheet / ViewModel 起動を抑止する。`testDisabledKeywordSettingsRouteGateSuppressesDefensivePresentation` で検証。
- 2.4 — `.nextPhaseEnabled` では keyword settings presentation が維持される。`testEnabledKeywordSettingsRouteGateKeepsExistingPresentationFlowReachable` で検証。
- 2.5 — `DisabledKeywordRepository` は全 method で network dependency なしに disabled error を返す。`testDisabledKeywordRepositoryFailsWithoutNetworkDependency` / `testDisabledKeywordRepositoryMutationsFailWithoutNetworkDependency` で検証。
- 3.1 — `APNsDeviceRegistrationService.registerPushToken` は disabled 時に repository / access token provider を呼ばず `.skippedFeatureDisabled` を返す。`testDisabledDeviceTokenRegistrationSkipsRepositoryAndClearsState` と `testDisabledAPNsDeviceTokenCallbackDoesNotPostDeviceRegistration` で検証。
- 3.2 — `NotificationPermissionCoordinator` は disabled 時に authorized でも remote registrar を呼ばない。`testDisabledFeatureDoesNotRegisterRemoteNotificationsWhenAuthorized` で検証。
- 3.3 — disabled login completion 後の pending retry は `/api/devices` 相当の repository call を行わない。`testDisabledCompleteLoginRetryDoesNotPostDeviceRegistration` で検証。
- 3.4 — disabled session restore 後の pending retry は `/api/devices` 相当の repository call を行わない。`testDisabledRestoreRetryDoesNotPostDeviceRegistration` で検証。
- 3.5 — disabled logout は `DELETE /api/devices/{id}` 相当の repository call を行わない。`testDisabledLogoutSkipsDeviceUnregisterClearsStateAndShowsLogin` / `testDisabledLogoutUnregisterSkipsRepositoryAndClearsKnownDevice` で検証。
- 3.6 — disabled path は local stale device registration state を clear し、network 成功に依存しない。APNs service / logout disabled tests で state clear を検証。
- 3.7 — APNs service と permission coordinator の default は `.nextPhaseEnabled` で、既存 enabled registration / retry / unregister tests は維持されている。
- 4.1 — `APIClientDeviceRegistrationRepository` と request contract tests は維持されている。`DeviceRegistrationRepositoryTests` の POST / DELETE / refresh retry tests で確認。
- 4.2 — `APIClientKeywordRepository` と request contract tests は維持されている。`KeywordRepositoryTests` の GET / POST / PATCH / DELETE / refresh retry tests で確認。
- 4.3 — `KeywordSettingsViewModelTests` の loading / mutation / error mapping coverage は維持されている。
- 4.4 — `KeywordSettingsSheet` は削除されず、enabled repository / access token で構築可能。`testEnabledKeywordSettingsSheetCanBeConstructedWithRepositoryAndAccessToken` で検証。
- 4.5 — notification article deep link source の production 差分はなく、既存 `NotificationArticleNavigationTests` が維持されている。
- 5.1 — `README.md` の v1 Smoke Test Checklist に `/api/devices` と `/api/keywords` は v1 default 成功条件外と明記されている。
- 5.2 — production default / disabled runtime / disabled repository の no-network 回帰 tests が追加され、device registration と keyword repository API call suppression を検証している。
- 5.3 — enabled configuration と existing next phase components の repository / ViewModel / sheet coverage が維持されている。
- 5.4 — `impl-notes.md` に full `xcodebuild ... test` 成功（468 tests / 0 failures）が記録されている。Reviewer でも `plutil -lint Feedman.xcodeproj/project.pbxproj` と `git diff --check develop..HEAD` の成功を確認した。

## Findings

なし

## Summary

AC 1.1-5.4 は実装または XCTest / README / impl-notes の検証記録で確認できた。変更パスは tasks.md の boundary に対応する AppEnvironment、notification service、AppShell route gate、disabled repository、regression tests、README 更新に収まり、boundary 逸脱は検出しなかった。

RESULT: approve
