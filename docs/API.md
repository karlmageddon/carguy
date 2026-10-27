# API contract

All `/v1` routes require `Authorization: Bearer <device token>` when a token is configured. `/health` is public but only reports configuration flags; `researchConfigured: true` does not prove provider access.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Process/storage mode/research-binding/auth flags |
| GET | `/v1/snapshot` | Complete personal library |
| POST | `/v1/sync` | Merge cars, exhibits, attempts, sessions and reports; return full snapshot |
| POST | `/v1/cars/{id}/research` | Run sourced web research and store validated facts |
| POST | `/v1/reports/{id}/review` | Recheck a reported fact and retain its previous revision |

OpenAPI is served at `/openapi.json` by FastAPI; schema fields use camelCase. Snapshot collections: `cars`, `exhibits`, `facts`, `attempts`, `sessions`, `reports`, `research`. Sync accepts only user-editable/activity collections, not facts or research results.

Timestamps are Unix seconds. IDs contain 1–100 ASCII letters, digits, `_` or `-`. Photos are optional base64 JPEGs of at most 250 KiB. Car identity notes should include placard transcription, variant and provenance uncertainties rather than guessed specifics. Source URLs must use HTTPS without credentials.

A sync is atomic within a request. Stale car timestamps are ignored. Attempts are graded by the backend against their specified fact revision. Reusing an immutable ID for different content returns 409. A session must reference its own existing attempts and a completion date consistent with its timestamp/time zone. Reporting a current fact immediately marks it `flagged`; reporting an obsolete revision is `superseded` instead.

Research has a five-minute lease to prevent concurrent duplicate work. Failed provider calls return 503 without publishing unvalidated facts. Research defaults to explicitly model-level facts. A clear model can return `ready` while the exhibited vehicle's exact year/body/provenance remains unknown. Unresolved contradictory identifiers or material model ambiguity return `needs_clarification`, with supported model-level or foundational facts still allowed. Clarification should be one concise question answerable in text identification notes, such as a museum placard transcription. Selected study photos are not supplied to research. Reviews return `corrected`, `reaffirmed` or `unresolved`; resolved results create a new fact revision. Provider response text is never exposed in credential error messages.

Firestore namespace: database `carguy`, `carguy_users/personal/<collection>/<id>`, with internal `fact_versions` and `review_jobs` collections. Clients use the API, not direct Firestore writes. Firestore transactions are limited to 450 changed records by the storage adapter; use bounded sync batches. This full-library transaction adapter targets a personal library, not high-volume multiuser workloads.

The provider's private output contract uses `distractors`, separate from the stored/API `choices` field. The backend adds the exact canonical answer and selects three distinct incorrect alternatives from the proposed pool, excluding accepted aliases and numeric equivalents. If fewer than three usable alternatives remain, research fails without publishing facts. The complete assembled question then passes the original `FactDraft` validators and source-evidence checks. The public schema and saved facts are unchanged; no migration or history reset is needed.
