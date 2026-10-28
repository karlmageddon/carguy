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

## Post-deployment sync verification — October 27, 2026

After the Actions deployment, the paired iPhone 16 Pro simulator running iOS 18.6 synced successfully with Cloud Run revision `carguy-api-00004-t46`, serving the image built from merge commit `43c8cd5`. The app displayed “Synced. Study is available offline.” using its saved pairing.

Before sync, the simulator and authenticated API snapshot matched: 7 cars, 10 facts, 3 answers, 1 completed session and 1 research status, with no exhibits or reports. Per-record fingerprints covered every stored field, normalizing equivalent JSON integer/float encodings and omitted optional null values. Comparing both snapshots after sync and again after restarting the app confirmed that every existing record remained unchanged, with no duplicates or lost data.

The two correct answers and one missed answer retained their grades, fact revisions and session references. Fact content and citations were unchanged. In the app, Ford Model T showed its published facts and “3 answers retained”; Study showed the completed session, a one-day streak and 8 facts due.

No new answers, sessions or research requests were created during this check, and no fixes were needed. The device token remained out of chat, logs and commits; temporary verification scripts and record fingerprints were removed. This verifies authenticated sync and existing-data preservation after deployment, without extending the earlier offline, photo or physical-device test coverage.


## Research photo galleries

Research targets 3–5 different best-match photos and labels them as representative when the precise year, variant or exhibited vehicle is uncertain. It stores the available matches even when fewer than three can be found. Sync saves the compact image copies and credits with the local library, so the gallery works without internet access. Existing personal photos are preserved as a fallback for cars without a gallery.

Garage → car → Photos includes **Next photo** and source/license credits. During study, successive questions about the same car cycle through its photos; each car has its own rotation. Existing cars need another Research after the gallery-capable backend is deployed to populate photos. No existing facts, answers or sessions need to be reset.


## Verified production photo galleries — October 27, 2026

After [PR #2](https://github.com/karlmageddon/carguy/pull/2) merged as `a96ee49`, the [Actions run](https://github.com/karlmageddon/carguy/actions/runs/40558418964) passed backend checks and all 15 iOS simulator tests, then deployed healthy Cloud Run revision `carguy-api-00005-7tl` with 100% of traffic.

One authorized Ford Model T research request returned five distinct representative photos. The response and a subsequent API snapshot matched exactly, confirming database persistence. All five copies decoded as valid JPEGs, measured approximately 74–88 kB each (all below 100 KiB), and included source, attribution and license metadata. Research retained `needs_clarification` for the exact exhibited vehicle, while still storing the best-match gallery and bringing the library to 20 facts. Fingerprint comparisons confirmed that all original facts, answers and completed sessions were preserved.

The paired iPhone 16 Pro simulator running iOS 18.6 synced the gallery and facts successfully. All five image copies and research metadata matched the API. After restarting with the temporary unreachable API URL, Sync failed as expected, but the gallery displayed its saved images and credits; **Next photo** showed another image without API access.

An offline quiz displayed photo 1 of 5. After one correct test answer, **Next question** changed to photo 2 of 5 with its corresponding credit and license. Finish saved the one-answer session locally. Another offline restart retained all five image copies, the answer and completed session. Restoring the saved production URL and syncing uploaded the test records successfully: the simulator and API matched at 7 cars, 20 facts, 4 answers and 2 completed sessions, with all original record fingerprints unchanged.

The simulator was left connected to production on the Ford Model T gallery. No code fixes were needed. This validates production photo research, database storage, sync, persistence and quiz rotation with the API unreachable; full network disconnection, physical-device behavior and personal-photo fallback were not additionally tested. The device token stayed out of chat, logs and commits, and temporary verification scripts and fingerprints were removed.


## Add a car by photographing its plaque

In Garage, choose **Add car by plaque**, then **Take plaque photo** or **Choose plaque photo**. Camera capture requires camera permission and supported hardware; saved-photo import is also available. Hold the plaque square to the camera and fill the frame with readable text.

Text recognition runs on-device. Review the suggested car name and the entire transcription, correcting years, model numbers and units against the photo. You can assign an exhibit and then choose **Save car** to keep the entry offline, or **Save and research** to save it and start the existing API research flow. No car is saved automatically when a photo is selected. Blank or unreadable text needs a clearer image or manual correction, and the app keeps over-limit text visible for editing instead of truncating it.

The reviewed transcription becomes identification notes with a museum-plaque label. A compact JPEG copy (at most 250 KiB) is saved separately as the museum plaque and synced to the private API. It remains available in car details across restarts and never becomes a quiz photo. Use Edit to correct the identification notes or remove the plaque photo; removing that photo preserves the notes. An existing matching car name is flagged in the review screen so you can cancel and edit that car instead of adding a duplicate.

Only the reviewed car name and identification notes are sent to OpenAI by research; plaque image bytes stay in the app/API library. Offline saving does not require a configured API. If online research fails, the saved entry remains available to retry later.

Validation for this change includes actual on-device OCR of a generated plaque image, identification-heading parsing, invalid-image handling, compact JPEG output, separate plaque/quiz-photo persistence, API round-trip and size validation, and confirmation that photo bytes are absent from provider research payloads. Physical iPhone camera capture has not yet been validated. The initial UI check could not automate system photo selection; the subsequent production verification below completed the import, review, save, sync and research flow.


## Verified plaque import and research — October 27, 2026

[PR #3](https://github.com/karlmageddon/carguy/pull/3) passed CI and merged as `de0f4f5`. Its [Actions deployment](https://github.com/karlmageddon/carguy/actions/runs/40572191185) passed backend checks and all 19 iOS simulator tests, then deployed healthy revision `carguy-api-00006-nz8` with 100% of traffic. No CI or deployment fixes were needed.

The paired iPhone 16 Pro simulator running iOS 18.6 imported a generated image headed “DELOREAN DMC-12” and explicitly labeled “PLAQUE IMPORT TEST” and “Synthetic test image, not a museum placard.” This was a test fixture, not evidence about a real museum exhibit. On-device OCR populated the name and full transcription. After reviewing the text, the name was changed to **DeLorean DMC-12 (plaque import test)** and **Save car** was used while the API URL was temporarily unreachable.

The car, reviewed identification notes and separate 143,696-byte plaque JPEG survived an offline app restart. The plaque was visible in car details and `photoData` remained empty, confirming that it was not used as a personal quiz photo. After restoring the saved production URL, Sync succeeded. An independent API snapshot matched the saved car, transcription and plaque bytes exactly.

Research was then started from that car's detail screen. The first request returned 503 because the source-evidence validator rejected an unverified source URL; it published no facts and preserved the saved entry. A retry with the same reviewed notes succeeded with `ready`, 11 published facts and five representative research photos. The result persisted in the API and matched the simulator, including after a final app restart.

Fingerprint comparisons confirmed that all pre-existing cars, facts, answers and completed sessions remained unchanged. The clearly labeled test entry was retained, and the simulator was left on its researched details. The device token stayed out of chat, logs and commits; temporary verification scripts, identifiers and fingerprints were removed.

This confirms saved-photo import, actual on-device OCR, editable review, offline save, restart persistence, production sync and subsequent research. **Save car**, Sync and **Research with OpenAI** were exercised as separate steps; the combined **Save and research** button was not separately tested end to end. Physical iPhone camera capture, full network disconnection and OCR accuracy on real museum photographs remain unverified.

## Current Study and Settings flow

Study is the default landing tab. Tap **Start quiz**, select exhibit checkboxes, then **Begin quiz**. Every exhibit is selected initially each time the picker opens; **All exhibits** selects or clears the group. **Unassigned cars** includes cars without an exhibit. Multiple exhibits can be combined. Cancel returns to Study; an empty selection or a selection with no due facts disables Begin quiz.

Every quiz is multiple choice and untimed. Choose an answer, tap **Check answer**, and continue with **Next question**. Tap **Finish** whenever ready. Only explicitly completed sessions containing answers count toward the streak. There is no duration control, typed-recall option, countdown, or deadline.

Offline-study information and **Sync library** are in **Settings → Offline study and sync**. Sync is manual. The redundant pairing-section Sync now button was removed; Garage retains its Sync action. Study no longer shows session settings, the offline note, or a sync button.

The iPhone 16 Pro simulator (iOS 18.6) verified the default checklist selection, empty-selection guard, and untimed quiz launch. The library used for this UI check contained unassigned cars; the regression test covers combinations of named exhibits, unassigned cars, and removed-car exclusion. All 20 iOS tests passed. The Settings relocation built successfully. No new answers or API sync were performed during these checks.
