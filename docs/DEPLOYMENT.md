# Deploying the recovered backend

Existing resources supplied by the owner:

| Resource | Value |
| --- | --- |
| Project | `orakle-1792087003` |
| Region | `us-west1` |
| Cloud Run | `carguy-api` |
| Firestore database | `carguy` (not `(default)`) |
| Existing OpenAI secret | `carguy-openai-key` |

This managed workspace has no connected GCP identity or usable Application Default Credentials. The owner has verified these resources in Google Cloud Shell and connected the existing OpenAI secret. Revision `carguy-api-00002-n7p` reports healthy Firestore, research configured and authentication required. A real Ford Model T research request returned 503 during source/question validation; no new facts were published by that failed request. End-to-end research validation remains outstanding.

## Access prerequisites

Use an authenticated Google Cloud SDK shell with this project's access, or connect a GCP identity to the cloud environment. Never paste credentials into chat or commit credential files. The managed cloud runtime's default identity must be selected explicitly when multiple identities are available. Existing GitHub authentication is separate and already works.

The deployer needs Cloud Run update/read, Cloud Build submission/logs, Artifact Registry repository read/create, permission to act as the existing runtime service account, secret metadata read and secret IAM update. The Cloud Build account needs permission to push the image into Artifact Registry. The runtime service account needs Firestore data access (`roles/datastore.user`, scoped appropriately) and Secret Manager accessor on the two secrets below. Enable the Cloud Run, Cloud Build, Artifact Registry, Firestore and Secret Manager APIs if not already enabled.

Inspect service identity, networking, current revision and IAM first:

```sh
gcloud run services describe carguy-api --project orakle-1792087003 --region us-west1 \
  --format='yaml(status.url,status.latestReadyRevisionName,spec.template.spec.serviceAccountName,spec.template.metadata.annotations)'
gcloud run services get-iam-policy carguy-api --project orakle-1792087003 --region us-west1
gcloud firestore databases describe --project orakle-1792087003 --database=carguy
```

Avoid dumping a service's complete environment: an older configuration might contain literal secrets. Do not read secret values merely to check existence. Verify that the runtime account has the required Firestore role before deploying; the helper deliberately does not grant broad project roles or change the service account.

For a device making direct requests, Cloud Run must permit invocation to reach FastAPI, which enforces its own long random pairing token on `/v1`. Preserve the existing IAM policy. If Cloud Run currently requires Google IAM identity tokens, the current iOS client cannot use that policy; configure an approved gateway/authentication path or explicitly review allowing public invocation while retaining FastAPI token protection. The deploy helper does not change public invocation or ingress.

## Connect the secrets

The OpenAI key already exists as `carguy-openai-key`; reuse it. Its latest enabled version must contain a working OpenAI API key. Do not create a duplicate just because the current cloud shell has no key environment variable.

The backend also requires a distinct device pairing secret containing at least 32 random characters. If an existing device-token secret is in use, reuse its name. Otherwise create `carguy-device-token` securely in Secret Manager, for example with a generated random value piped directly to the CLI, and retrieve it through a secure owner-controlled path when pairing the phone. Never use the OpenAI API key as the device token.

```sh
# Only if this device-token secret does not already exist:
openssl rand -hex 32 | gcloud secrets create carguy-device-token \
  --project orakle-1792087003 --replication-policy=automatic --data-file=-
```

## Build and update

From the repository root, with a clean, committed checkout:

```sh
export CARGUY_DEVICE_SECRET=carguy-device-token  # A secret NAME, not a value
bash scripts/deploy.sh
```

The helper verifies existing resources, retains the runtime account, grants that account accessor on the named secrets, creates the Docker Artifact Registry repository `carguy` only if absent, builds an image tagged with the current Git commit using Cloud Build, and updates the existing Cloud Run service. Its secret bindings are:

```text
CARGUY_RESEARCH_API_KEY = carguy-openai-key:latest
CARGUY_DEVICE_TOKEN     = <CARGUY_DEVICE_SECRET>:latest
```

Its non-secret runtime settings are:

```text
CARGUY_ENV=production
CARGUY_STORE=firestore
CARGUY_PROJECT_ID=orakle-1792087003
CARGUY_FIRESTORE_DATABASE=carguy
```

The request timeout is set to 300 seconds to accommodate sourced research. The script updates named environment settings/secrets; it does not replace unrelated variables, reset service IAM, change ingress, or create a new Firestore database. Review deployment output and IAM permissions if a step fails before retrying. Do not recreate existing resources to work around an access denial.

The recovery's Dockerfile uses Python 3.12 and pinned uv with `uv sync --frozen --no-dev --no-install-project`. Cloud Build publishes to `us-west1-docker.pkg.dev/orakle-1792087003/carguy/api:<commit>`. For local Docker builds in a managed environment, follow the runtime Docker proxy and CA guidance before building; never disable TLS or checksum verification.

## Verify storage and real research

1. Get the service URL from the deploy output or `gcloud run services describe ... --format='value(status.url)'`.
2. Request `/health`. Expect `storage: firestore`, `authenticationRequired: true`, and `researchConfigured: true`. These flags only verify configuration.
3. Pair iOS Settings with that HTTPS URL and the device token. Sync the starter library. Restart the app, sync again, and confirm the server retained the library in database `carguy`.
4. Research the Detroit Electric. This makes a paid OpenAI request with web search. Confirm either a sourced resolution or an explicit `needs_clarification`; “1905” must not be silently accepted. If a placard is required, enter it in identification notes and retry.
5. Research another clearly identified car. Confirm stored technical, history, story and fundamentals facts have actual source links in fact details. Study in airplane mode with a selected car photo; complete a session, reconnect and Sync.
6. Flag a fact, request agent rechecking, and verify it remains absent from quizzes until resolved. Confirm old attempts remain after any correction.

A CLI alternative to app seeding/research is `uv run python scripts/seed_starters.py --api "$CARGUY_API_URL" --research`, with `CARGUY_DEVICE_TOKEN` supplied securely to that process. Omit `--research` to avoid paid calls. Do not put tokens into shell command arguments/history or debug traces. The script prints statuses, never tokens.

If OpenAI fails, inspect revision logs and check secret-version state, runtime accessor permissions, API quota/model access and egress. Do not print upstream credential headers or disable verification. An HTTP 503 deliberately leaves unvalidated facts unpublished. A configured key alone does not prove provider success.

## Network settings

Cloud-machine GitHub/Python dependency access currently works through the supplied proxy. Remote Google API/identity operations may need `run.googleapis.com`, `firestore.googleapis.com`, `secretmanager.googleapis.com`, `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`, `cloudresourcemanager.googleapis.com`, `iam.googleapis.com`, `iamcredentials.googleapis.com`, `oauth2.googleapis.com`, `sts.googleapis.com` and `storage.googleapis.com` in environment settings. The OpenAI destination is `api.openai.com`. Actual Cloud Run service hostnames are discovered from the service; add the specific hostname for cloud-machine smoke tests once known.

These are distinct from the Cloud Run service's own VPC/egress configuration. Adding a cloud-machine allowlist does not modify Cloud Run networking or supply GCP credentials. The app needs HTTPS access to its Cloud Run endpoint; offline study does not need network access.

## Rollback

Record the ready revision name before changing the service. To roll traffic back after diagnosing a bad revision, use the Cloud Run console or `gcloud run services update-traffic carguy-api --project orakle-1792087003 --region us-west1 --to-revisions=<previous-ready-revision>=100`. This changes traffic, not stored learning data. Do not delete the Firestore database or reset secret versions as a rollback mechanism.

## Diagnosing rejected research output

For the error “Research did not pass source and question validation”, the provider returned a completed response but the backend rejected its structured facts, quiz semantics or source evidence. The API response combines those causes. The recovered image does not record the underlying rule; updated images log a bounded `Research output rejected:` diagnostic containing only rule identifiers, field locations and fixed validator messages.

In an authenticated Google Cloud SDK shell, from a current checkout with dependencies installed, run:

```sh
uv run python -m scripts.diagnose_research
```

This reads the deployed service's secret references, uses the referenced credentials internally, fetches the saved Ford Model T identification, and makes **one paid diagnostic OpenAI request**. It does not write facts or alter the live library. It prints only safe validation field names, rule identifiers and allowlisted validator messages. Do not print raw exceptions or provider bodies: validation errors can include input data. Share the diagnostic JSON, not credentials.

A fresh diagnostic response can pass even after a previous output failed; generation is nondeterministic. Diagnose the rule before changing prompts or retrying. Keep all source-evidence and question checks in place.

## Deploying the question-generation fix

The owner's direct diagnostic reproduced three questions rejected for duplicated choices or omission of the exact canonical answer. The backend now requests a pool of incorrect alternatives and assembles the correct choice itself, then runs the original question and source validators. This removes the requirement for OpenAI to copy the answer identically into two fields. No source claims are relaxed, and no existing learning history changes.

From the current checkout in Google Cloud Shell:

```sh
git pull --ff-only
bash scripts/deploy.sh --image-only
uv run --frozen python -m scripts.cloud_smoke
```

If uv was installed in the diagnostic bootstrap environment, use `.bootstrap/bin/uv` instead of `uv`. The image-only deployment preserves the existing service account, secret bindings and versions (including device token version `1`), environment variables, ingress, IAM policy and timeout. It still builds and publishes a new image through Cloud Build.

The smoke command reads only the device-token secret, makes one paid research request for the existing Ford Model T entry, fetches the stored result again, and validates each published question. It never reads the OpenAI key locally and does not seed or overwrite cars. Success is evidence of the live research/storage path; it does not validate every historical claim or the iOS client.
