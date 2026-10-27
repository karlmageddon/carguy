# Carguy

A personal iOS study companion for learning to be a Petersen Automotive Museum docent. Enter cars, group them by exhibit, research sourced facts with OpenAI, and practice with photos and spaced repetition.

The FastAPI backend was recovered from `carguy-backend.tgz`; the SwiftUI app and documentation were recreated after the original workspace was lost. The original commit `d4cfff9` was not available from GitHub. Recovery begins at `b592595`; original Git history could not be reconstructed from a source archive.

## What's implemented

- Garage with exhibits, identification notes, photo import and removed-car status. Removed cars leave the quiz pool; their facts, attempts, sessions and exhibit history remain.
- OpenAI web research for technical specifications, history, stories and automotive fundamentals. Facts must cite URLs returned by web search and pass question validation before storage. This validates source provenance, not the truth of every claim; disputed facts can be quarantined and rechecked.
- Multiple-choice and typed recall, including explicit numeric-unit/tolerance grading. Citations appear in fact details, outside the quiz.
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

In the app's Settings, enter the HTTPS Cloud Run URL and save its device token to Keychain. Then Sync. The OpenAI key belongs on the backend, never in the iOS app. Choose your own or licensed car photos in Garage → Edit; selected JPEGs are compressed below 250 KiB and stored with the offline library. Research photo links are references, not automatically downloaded or represented as licensed images.

## Starter identifications

The library begins with Detroit Electric Model 61 Brougham, Lancia Delta S4, 1933 Duesenberg, Ford Model T, Benz Patent-Motorwagen and Czinger 21C. No automotive claims are pre-published.

**The supplied Detroit Electric year “1905” remains unverified.** It is recorded as a question in identification notes, not accepted as fact. Research must resolve the year/model using primary or museum sources before publishing specific claims. A generic “1933 Duesenberg” also needs model/chassis/coachbuilder or placard details; the Delta S4 needs road versus competition identification. Model-level facts can be researched while provenance remains unresolved.

## Deployment and current validation

See [deployment](docs/DEPLOYMENT.md), [API contract](docs/API.md) and [recovery record](docs/RECOVERY.md).

Current cloud-machine checks: 15 backend tests and Ruff pass; the running local API returns health and a persisted six-car starter snapshot; a second seed creates zero duplicates. An absent OpenAI binding correctly returns 503 instead of fabricated research. The managed workspace has no usable GCP identity. Separately, the owner used Google Cloud Shell to verify the service, named database and secret, grant the runtime account secret access, and connect `CARGUY_RESEARCH_API_KEY`. Revision `carguy-api-00002-n7p` serves a healthy authenticated Firestore API. A live Ford Model T research request reached output validation but returned 503; no new facts were published by that failed request. Research is not yet verified end to end. The recreated iOS app still requires Xcode simulator/device validation.
