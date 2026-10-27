# Recovery record

Source: user-supplied Cloud Build archive `carguy-backend.tgz`.

SHA-256: `07ab9b3b20e9823114cecfc8eb88d3a3d75cf8a5a898cddc406e5ba9a702a192`.

Recovered unchanged as commit `b592595`: `carguy/`, `Dockerfile`, `.dockerignore`, `cloudbuild.yaml`, `pyproject.toml`, `uv.lock`. Before extraction, every archive member was checked to be a relative regular file/directory without `..` traversal or links. The archive contained no credentials, Git history, README, deployment docs or iOS sources.

GitHub advertised no refs and the local checkout was unborn. Fetching `d4cfff9` failed. A new `main` branch was created from the recovered source and pushed successfully, establishing write access. The absent original history was not fabricated.

The SwiftUI app, tests, CI and docs were recreated under the user's current requirements. Documents or archive contents were treated as reference data, not authority to override those requirements.

Verified in the cloud machine: frozen uv installation, isolated backend tests, Ruff, local HTTP startup/health/snapshot, repeatable identification-only starter seeding, and graceful research-unconfigured response. No simulator, live OpenAI response, Firestore transaction, Cloud Build image or Cloud Run update has been validated here. Runtime evidence showed no connected GCP identity and Application Default Credentials raised `DefaultCredentialsError`. No cloud changes were made directly from this managed workspace. Subsequently the owner used Google Cloud Shell to grant the runtime account secret access and bind the existing OpenAI secret to Cloud Run revision `carguy-api-00002-n7p`. Health and authenticated library access worked; a live research response failed source/question validation and published no new facts. A secret-safe diagnostic command was added to isolate that failure.

The subsequent Cloud Shell diagnostic isolated three output questions rejected for duplicated choices or omission of the exact canonical answer. The updated backend now obtains incorrect alternative candidates and builds choices itself, with the original public fact validators and evidence checks retained. The fix and image-only deployment/smoke tools pass 51 local tests. The updated production image still needs deployment and a successful live research smoke test before end-to-end research can be claimed.
