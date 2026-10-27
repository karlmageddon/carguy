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

Run **Product → Test** (**Command-U**) to execute the `CarguyTests` suite. These tests have been added but have not run in the Linux cloud workspace. If a build or test fails, share the first relevant Xcode error and file/line; do not share credentials.

## Pair and sync

In the running app's Settings:

1. Set the HTTPS API URL to `https://carguy-api-241317397030.us-west1.run.app`.
2. Open the owner-controlled Google Cloud Secret Manager console for `carguy-device-token` in project `orakle-1792087003`. View/copy **version 1**, which the service currently uses, into the app's Device token field. Save it to Keychain. Keep this value out of chat, source files and screenshots.
3. Tap **Sync now**. In Garage, open the Ford Model T entry and its facts. Citations appear in fact details. Study draws from published facts even if a research identification question remains unresolved.

The OpenAI key remains on the backend. The app does not need it. Research receives the car's name and text notes; use Garage → Edit to transcribe placard details. Selected car photos are saved for offline study and are not inspected by research.

## Try offline study

Choose a car photo in Garage → Edit, start a study session, answer a few questions and Finish. Then disconnect the simulator's network (or use airplane mode on a physical device) and confirm saved facts/photos remain usable. Reconnect and Sync to upload answers and sessions. Sources stay outside quizzes.

For a physical iPhone, choose your signing team under the app target's Signing & Capabilities, connect/select the phone and run. Follow Xcode's device trust/developer-mode prompts if shown. Validate on the simulator first so signing issues do not obscure application build failures.
