# Recovery record

Source: user-supplied Cloud Build archive `carguy-backend.tgz`.

SHA-256: `07ab9b3b20e9823114cecfc8eb88d3a3d75cf8a5a898cddc406e5ba9a702a192`.

Recovered unchanged as commit `b592595`: `carguy/`, `Dockerfile`, `.dockerignore`, `cloudbuild.yaml`, `pyproject.toml`, `uv.lock`. Before extraction, every archive member was checked to be a relative regular file/directory without `..` traversal or links. The archive contained no credentials, Git history, README, deployment docs or iOS sources.

GitHub advertised no refs and the local checkout was unborn. Fetching `d4cfff9` failed. A new `main` branch was created from the recovered source and pushed successfully, establishing write access. The absent original history was not fabricated.

The SwiftUI app, tests, CI and docs were recreated under the user's current requirements. Documents or archive contents were treated as reference data, not authority to override those requirements.

Initial cloud-machine verification covered: frozen uv installation, isolated backend tests, Ruff, local HTTP startup/health/snapshot, repeatable identification-only starter seeding, and graceful research-unconfigured response. At that stage, no simulator, live OpenAI response, Firestore transaction, Cloud Build image or Cloud Run update had been validated there. Runtime evidence showed no connected GCP identity and Application Default Credentials raised `DefaultCredentialsError`. No cloud changes were made directly from this managed workspace. Subsequently the owner used Google Cloud Shell to grant the runtime account secret access and bind the existing OpenAI secret to Cloud Run revision `carguy-api-00002-n7p`. Health and authenticated library access worked; a live research response failed source/question validation and published no new facts. A secret-safe diagnostic command was added to isolate that failure.

The subsequent Cloud Shell diagnostic isolated three output questions rejected for duplicated choices or omission of the exact canonical answer. The updated backend now obtains incorrect alternative candidates and builds choices itself, with the original public fact validators and evidence checks retained. The fix and image-only deployment/smoke tools pass 51 local tests. At that stage, the updated production image still needed deployment and a successful live research smoke test before end-to-end research could be claimed.

After deployment, the owner reported 10 persisted sourced Ford Model T facts passing the inspection checks, with `needs_clarification` requesting the specific year/body style. This confirms live sourced research and storage while retaining identity uncertainty. Subsequent scope guidance defaults clear named models to model-level learning, asks concise text-note questions when necessary, and avoids unsupported photo/document-upload requests. No stored facts or research statuses were rewritten by that guidance change.

On October 26, 2026, the Mac checkout was built and run using Xcode 16.4 on an iPhone 16 Pro simulator with iOS 18.6. Enabling generated Info.plist creation for the test target in `ios/project.yml` resolved the test build failure; all 12 iOS tests passed. The 64 backend/deployment-tool tests and Ruff passed on the Mac as well. The existing Cloud Run service was healthy, and pairing through simulator Keychain and authenticated sync survived an app restart.

A three-answer session with a temporary unreachable API URL saved two correct answers, one incorrect answer and a completed session locally. Those records survived a restart while the API remained unreachable and were absent from the server before sync. Restoring the saved Cloud Run URL and syncing produced exactly matching attempts, grades and session data on the API; repeat sync created no duplicates. The missed question became due again. This verified API-unavailable study, not full network disconnection, selected-photo persistence or physical-device behavior. No new research request or backend deployment was made during these Mac checks. The device token remained out of chat, logs and commits. See [the iOS verification record](IOS.md) for the procedure and limits.
