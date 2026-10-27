# Carguy

A personal iOS study companion for learning to be a Petersen Automotive Museum docent. Enter cars, group them by exhibit, research sourced facts with OpenAI, and practice with photos and spaced repetition.

The FastAPI backend was recovered from `carguy-backend.tgz`; the SwiftUI app and documentation were recreated after the original workspace was lost. The original commit `d4cfff9` was not available from GitHub. Recovery begins at `b592595`; original Git history could not be reconstructed from a source archive.

## What's implemented

- Garage with exhibits, identification notes, photo import and removed-car status. Add car by plaque captures or selects a museum plaque, reads its text on-device, and lets you review the name and transcription before saving or researching. Plaque images are kept separately from quiz photos. Removed cars leave the quiz pool; their facts, attempts, sessions and exhibit history remain.
- OpenAI web research for technical specifications, history, stories and automotive fundamentals. Facts must cite URLs returned by web search and pass question validation before storage. This validates source provenance, not the truth of every claim; disputed facts can be quarantined and rechecked.
- Multiple-choice and typed recall, including explicit numeric-unit/tolerance grading. OpenAI proposes incorrect alternatives; the backend adds the exact canonical answer, removes duplicate/equivalent alternatives, and validates the assembled question before publication. Citations appear in fact details, outside the quiz.
- Local persistent library, offline answers and reports, manual sync, immutable attempts, versioned facts, and server-side regrading against the original fact revision.
- Due-first repetition: a missed answer returns after one minute; successive correct answers schedule 1, 2, 4, 8, 16 and then 30 days. A revised fact starts fresh.
- Session targets from 5–30 minutes, early Finish, daily local reminders, daily streaks and three automatic freezes per calendar month. A completed session requires an answer; freezes preserve a streak without adding study days or banking unused freezes. See [learning behavior](docs/LEARNING.md).

## Backend development

Requires Python 3.12+ and uv. Commands run from the repository root:

```sh
export UV_CACHE_DIR=/workspace/.cache/uv  # Writable cache in the managed cloud machine
uv sync --frozen
uv run pytest -q
uv run ruff check .
uv run uvicorn carguy.main:app --host 127.0.0.1 --port 8080
```

In another terminal:

```sh
uv run python scripts/seed_starters.py
```

The local SQLite store is `.data/carguy.sqlite` (ignored by Git). Starter seeding is idempotent and does not overwrite existing entries or invent facts. Local development has no authentication unless `CARGUY_DEVICE_TOKEN` is set; bind to loopback. Production refuses to start without Firestore and a device token of at least 32 characters.

Tests use isolated SQLite databases and a mocked research provider. They do **not** demonstrate live OpenAI access or Firestore deployment. Source URLs in fixtures are test data.

## iOS development

Requires macOS, Xcode 15+ and XcodeGen; minimum iOS 17. The Linux cloud workspace cannot compile or run the iOS app.

```sh
brew install xcodegen
xcodegen generate --spec ios/project.yml
open ios/Carguy.xcodeproj
```

Choose your signing team in Xcode and run the `Carguy` scheme. Run the `CarguyTests` suite on an available iPhone simulator. GitHub Actions also defines a macOS simulator job; a configured job is not evidence of a successful build.

In the app's Settings, enter the HTTPS Cloud Run URL and save its device token to Keychain. Then Sync. The OpenAI key belongs on the backend, never in the iOS app. Choose your own or licensed car photos in Garage → Edit; selected JPEGs are compressed below 250 KiB and stored with the offline library. Research also finds up to five distinct best-match Commons photos and stores compact JPEG copies with source, attribution and reuse-license details in the database. Sync saves the gallery on the device for offline use, and quizzes rotate photos for each car. Images are labeled representative because the exact vehicle or variant may differ. Research targets 3–5 photos but retains smaller usable galleries when fewer are available.

## Starter identifications

The library begins with Detroit Electric Model 61 Brougham, Lancia Delta S4, 1933 Duesenberg, Ford Model T, Benz Patent-Motorwagen and Czinger 21C. No automotive claims are pre-published.

**The supplied Detroit Electric year “1905” remains unverified.** It is recorded as a question in identification notes, not accepted as fact. Research must resolve the year/model using primary or museum sources before publishing specific claims. A generic “1933 Duesenberg” also needs model/chassis/coachbuilder or placard details; the Delta S4 needs road versus competition identification. Model-level facts can be researched while provenance remains unresolved.

## Deployment and current validation

See [deployment](docs/DEPLOYMENT.md), [API contract](docs/API.md) and [recovery record](docs/RECOVERY.md).

The test workflow includes an optional Cloud Run deployment job gated on backend and iOS tests. Carguy-specific identity federation and repository variables control activation; see [GitHub Actions deployment setup](docs/GITHUB_ACTIONS.md).

Verified on the Mac on October 26, 2026: the `Carguy` scheme builds and runs on an iPhone 16 Pro simulator with iOS 18.6 using Xcode 16.4. All 12 iOS tests, 64 backend/deployment-tool tests and Ruff pass. The test target now generates its Info.plist through `ios/project.yml`. Pairing and sync with the existing Cloud Run API survive an app restart.

A three-answer study session with the API unreachable graded two answers correct and one incorrect, saved a completed session locally, and survived an app restart before sync. The API contained none of those records before sync; afterward, all three attempts (including grades) and the completed session matched exactly. Repeated sync created no duplicates, and the missed question became due again. This simulated API unavailability with a temporary unreachable URL; full network disconnection, selected-photo persistence and physical-device behavior remain unverified. See [the simulator results and procedure](docs/IOS.md).

After the Actions deployment on October 27, the paired simulator synced successfully with Cloud Run revision `carguy-api-00004-t46`. All 10 facts, 3 answers and 1 completed session matched the API before and after sync and an app restart; grades, citations, fact revisions and history were unchanged. The app retained its one-day streak. No fixes or new study records were needed; see [the post-deployment verification](docs/IOS.md#post-deployment-sync-verification--october-27-2026).

The photo-gallery feature is deployed in revision `carguy-api-00005-7tl`. Its [Actions run](https://github.com/karlmageddon/carguy/actions/runs/40558418964) passed backend checks and all 15 iOS simulator tests. A fresh Ford Model T research request persisted five representative photos, which synced exactly to the paired simulator, survived restarts and rotated between quiz questions with the API unreachable. The offline test answer/session synced after reconnecting; the library now contains 20 facts, 4 answers and 2 completed sessions, with original facts and history preserved. See [the production photo-gallery results](docs/IOS.md#verified-production-photo-galleries--october-27-2026).

Earlier cloud-machine checks verified local API health, a persisted six-car starter snapshot and duplicate-free repeat seeding. That managed cloud workspace had no usable GCP identity; the Mac can access the existing API using the owner's authorized Google account. The owner previously used Google Cloud Shell to connect the existing OpenAI secret and deploy the question-generation fix. That deployment stored 10 sourced Ford Model T facts that passed question validation; it reports `needs_clarification` for the particular vehicle's year/body style. Those facts are available for study. The latest repository guidance defaults to model-level research when the named model is clear and limits clarification to questions answerable in text notes; that guidance is included in the subsequently deployed photo-gallery image.

For an existing Cloud Run service, `bash scripts/deploy.sh --image-only` builds and updates just the image, preserving secret versions and runtime settings. Then run `uv run python -m scripts.cloud_smoke` in an authenticated Google Cloud SDK shell to make one paid research request and verify the resulting facts persist. The deployed question-generation fix produced 10 persisted Ford Model T facts; the later photo-gallery deployment also includes the newer research guidance.

To read the latest stored research status and identification question without making a paid request, run `uv run python -m scripts.cloud_smoke --inspect`. Inspection labels its output `inspectionOnly` and cannot reconstruct the preceding POST response. Normal smoke exits 0 for ready, 2 for a completed/persisted result needing identification clarification, and 1 for technical or consistency failures.

For step-by-step Mac setup and secure device pairing, see [running the iOS app](docs/IOS.md).
