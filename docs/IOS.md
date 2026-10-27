# Run Carguy on your Mac

Requires Xcode 15 or newer with an iOS 17+ simulator runtime. The cloud workspace runs Linux, so simulator/device builds must run on your Mac. The backend already has 10 sourced Ford Model T facts available to sync; no additional research request is needed to try studying.

## Open the project

In Terminal on your Mac, choose a folder where you keep projects:

```sh
git clone https://github.com/karlmageddon/carguy.git
cd carguy
brew install xcodegen
xcodegen generate --spec ios/project.yml
open ios/Carguy.xcodeproj
```

If you already have this checkout, preserve local edits and use `git pull --ff-only` from it instead of cloning over it. If `brew` is unavailable, install Homebrew using its official instructions at https://brew.sh, then install XcodeGen. The generated Xcode project is ignored by Git; the source of truth is `ios/project.yml`.

In Xcode, select the **Carguy** scheme and an available **iPhone simulator**. Run with **Command-R**. If no iPhone simulator is available, use Xcode's Platforms/Components settings (label varies by Xcode version) to download an iOS runtime. You can use the simulator before configuring device signing.

Run **Product → Test** (**Command-U**) to execute the `CarguyTests` suite. All 12 tests passed on the Mac simulator described below. The test target requires `GENERATE_INFOPLIST_FILE: YES`, now included in `ios/project.yml`; regenerate the project after updating that file. If a build or test fails, share the first relevant Xcode error and file/line; do not share credentials.

## Pair and sync

In the running app's Settings:

1. Set the HTTPS API URL to `https://carguy-api-241317397030.us-west1.run.app`.
2. Open the owner-controlled Google Cloud Secret Manager console for `carguy-device-token` in project `orakle-1792087003`. View/copy **version 1**, which the service currently uses, into the app's Device token field. Save it to Keychain. Keep this value out of chat, source files and screenshots.
3. Tap **Sync now**. In Garage, open the Ford Model T entry and its facts. Citations appear in fact details. Study draws from published facts even if a research identification question remains unresolved.

The OpenAI key remains on the backend. The app does not need it. Research receives the car's name and text notes; use Garage → Edit to transcribe placard details. Selected car photos are saved for offline study and are not inspected by research.

## Try offline study

Sync the library first and optionally choose a car photo in Garage → Edit. Disconnect before starting a study session, answer a few questions and tap Finish. Confirm the result is saved locally, restart the app while disconnected, and check your completed-session count. Reconnect and Sync to upload answers and sessions. Sources stay outside quizzes.

For a repeatable simulator check of API unavailability without disconnecting the Mac's network, terminate Carguy and launch it with a temporary URL override:

```sh
xcrun simctl terminate booted com.karlmageddon.Carguy
xcrun simctl launch booted com.karlmageddon.Carguy -apiURL https://127.0.0.1:1
```

With a single simulator booted, tap Sync and confirm it reports that it cannot connect. Study using the saved library, Finish, then repeat the commands above to verify persistence while the API remains unreachable. Restore the saved Cloud Run URL by terminating and launching without the override:

```sh
xcrun simctl terminate booted com.karlmageddon.Carguy
xcrun simctl launch booted com.karlmageddon.Carguy
```

Tap Sync again. The launch override does not replace the saved URL or Keychain token. This checks operation without API access; use airplane mode on a physical device to additionally validate full network disconnection and saved photos.

For a physical iPhone, choose your signing team under the app target's Signing & Capabilities, connect/select the phone and run. Follow Xcode's device trust/developer-mode prompts if shown. Validate on the simulator first so signing issues do not obscure application build failures.

## Verified simulator results — October 26, 2026

- Xcode 16.4 built and ran the `Carguy` scheme on an iPhone 16 Pro simulator running iOS 18.6. All 12 `CarguyTests` passed after enabling generated Info.plist creation for the test target. The 64 backend/deployment-tool tests and Ruff also passed on the Mac.
- The existing Cloud Run API reported healthy Firestore storage, research configured and authentication required. Pairing was saved to simulator Keychain; the saved API URL and authenticated sync worked after restarting without launch arguments. The existing personal Google account had direct project access; unrelated default work-account impersonation settings were left unchanged.
- Ten published Ford Model T facts were available. With the temporary unreachable API URL, Sync failed as expected, but multiple-choice study loaded saved questions and graded answers locally. A three-answer session finished early with two correct and one incorrect answer and showed that progress was saved on the device.
- Before restoring API access, an authenticated snapshot check confirmed that none of the three attempt IDs or the completed session existed on the server. Restarting with the unreachable URL retained the local session and a one-day streak.
- After restoring the saved URL and syncing, all three attempts, their grades and the completed session matched the API snapshot exactly. A second sync retained the same records without duplicates. The missed question became due again after the one-minute retry interval.

These checks used the stored facts and made no new research request. The offline check simulated API unavailability, not full network disconnection. Selected-photo persistence and physical-device behavior were not tested. The device token was handled privately, remained out of chat, logs and source control, and the simulator clipboard and temporary transfer resources were cleared after pairing.
