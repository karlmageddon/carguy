# GitHub Actions deployment to Cloud Run

The `Test` workflow runs backend tests/Ruff and the iOS simulator suite on pushes and pull requests. Its optional deployment job waits for both suites to pass for the same commit. Deployment is disabled unless the repository variable `CARGUY_DEPLOY_ENABLED` is `true`.

On a push to `main`, the workflow compares the previous push SHA with the new SHA. Changes under `carguy/`, or to the Dockerfile, Python dependency files, Cloud Build configuration, upload exclusions, deployment script or workflow, trigger deployment. Documentation-only and iOS-only pushes run tests without deploying. Pull requests never deploy. A first push with no previous SHA treats the backend as changed. Deployment jobs serialize without cancelling a running update and skip a commit if newer backend or deployment changes already exist on `main` when its deployment starts. A later documentation-only push does not suppress a pending backend deployment.

The job calls `bash scripts/deploy.sh --image-only`: Cloud Build builds the tested commit, pushes its commit-tagged image to the existing `carguy` Artifact Registry repository, and updates the image of `carguy-api` in `us-west1`, project `orakle-1792087003`. It preserves runtime identity, environment settings, pinned Secret Manager bindings, ingress and service IAM. A public `/health` check verifies Firestore, required authentication and configured research; it does not perform authenticated sync or paid research.

## Configure the identities before enabling deployment

Use [Google's Workload Identity Federation guidance](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) and the [authentication action's setup instructions](https://github.com/google-github-actions/auth). No service-account JSON key, device token or OpenAI key is needed in GitHub. The workflow does not access Secret Manager values. Generated `gha-creds-*.json` files are excluded from Git, Docker context and Cloud Build upload (the latter includes `.gitignore`).

Inspection on October 26, 2026 found an existing `github` federation pool and provider in this project. That provider trusts repository ID `1284312004`, while `karlmageddon/carguy` has ID `1432315798`. Do not repoint that provider or reuse the unrelated `orakle-deploy` account. Create a separate Carguy provider and deployment account, retaining the existing configuration for its owner.

1. Configure a provider for issuer `https://token.actions.githubusercontent.com`. Map the repository ID and any other claims used by its condition. Restrict it to numeric repository ID `1432315798`, `refs/heads/main`, the `push` event, and the workflow `.github/workflows/test.yml` on `main`. If using an owner restriction, obtain and use the numeric owner ID as well.
2. Grant that provider's Carguy principal `roles/iam.workloadIdentityUser` on a dedicated deployment service account. Limit its access to the existing Carguy resources: Cloud Build submission/read permissions, the source staging bucket, Artifact Registry repository inspection, Cloud Run image updates, and permission to act as the service's runtime identity and the Cloud Build execution identity. It does not need access to secret values, Firestore data, service IAM changes or project-wide administration. The repository already exists, so routine CI does not need repository-creation rights.
3. Preserve `carguy-runtime@orakle-1792087003.iam.gserviceaccount.com` as the runtime account. Cloud Build explicitly uses `carguy-build@orakle-1792087003.iam.gserviceaccount.com` through `cloudbuild.yaml`. Its existing `roles/run.builder` grant supplies image upload, source read and logging permissions. The deployment identity may act as this build account and the runtime account; it cannot act as the unrelated Compute Engine default account with project-wide Editor access.
4. Create a GitHub environment named `production`, restricted to `main`. Add required reviewers if each deployment should need approval. Set repository Actions variables:

   | Variable | Value |
   | --- | --- |
   | `CARGUY_WIF_PROVIDER` | Full resource name of the new Carguy provider |
   | `CARGUY_DEPLOY_SERVICE_ACCOUNT` | Dedicated Carguy deployment account email |
   | `CARGUY_DEPLOY_ENABLED` | Leave unset until configuration is complete; then set to `true` |

5. Push a reviewed backend change to `main` and watch both test jobs, image build/update and health verification. Record the ready revision before the first deployment using the command in [deployment guidance](DEPLOYMENT.md). Disabling `CARGUY_DEPLOY_ENABLED` stops future automated deployments; it does not cancel an update already running. Roll traffic back using the documented Cloud Run revision procedure if necessary.

## Carguy configuration — October 27, 2026

The dedicated pool is `carguy-github` and its provider is `github`, in project number `241317397030`. The deployment account is `carguy-deploy@orakle-1792087003.iam.gserviceaccount.com`. Federation requires repository ID `1432315798`, owner ID `3857309`, a push to `main`, the `Test` workflow file on `main`, and the exact `production` environment subject. This repository uses the immutable subject `repo:karlmageddon@3857309/carguy@1432315798:environment:production`; inspect `gh api repos/karlmageddon/carguy/actions/oidc/customization/sub` before configuring or changing this condition. The existing unrelated provider remains unchanged.

GitHub's `production` environment accepts only the `main` branch. The repository's provider and deployment-account variables point to the dedicated resources. The enable variable is now `true`; automatic deployment is active for qualifying pushes to `main`.

The deployment account has the custom `carguyCiBuildSubmitter` project role for build create/get/list, project lookup, service usage, build-log reading and bucket-name listing (required by the SDK staging-bucket ownership check); the custom `carguyCiSourceUploader` role on the existing source staging bucket; Artifact Registry Reader on the `carguy` repository; Cloud Run Developer on `carguy-api`; and Service Account User on only the Carguy runtime and build accounts. It has no Secret Manager accessor grant or service-account key. A successful local test or skipped deployment job does not demonstrate GitHub-to-GCP authentication or a completed production deployment; verify the actual Actions build and ready revision after merging.


## First verified Actions deployment — October 27, 2026

[PR #1](https://github.com/karlmageddon/carguy/pull/1) merged as `43c8cd50de37a808e50dff9bcc0182e135f13696`. The [Actions run](https://github.com/karlmageddon/carguy/actions/runs/40521884929) passed backend tests/Ruff and all 12 iOS simulator tests, then authenticated through federation, built the image and updated Cloud Run. Initial deployment-only retries corrected the immutable subject match and the SDK's bucket-list permission; the test gates remained successful.

Cloud Build `4b3ff1f7-44a0-4b86-a9db-926046388f1f` used `carguy-build` and published `us-west1-docker.pkg.dev/orakle-1792087003/carguy/api:43c8cd50de37`. Ready revision `carguy-api-00004-t46` received 100% of traffic. The preceding ready revision was `carguy-api-00003-7rd`, available for the documented traffic rollback procedure.

An independent live check confirmed healthy Firestore, required authentication and configured research. A before/after configuration fingerprint confirmed the runtime identity, environment/secret bindings, ingress and timeout were preserved. A harmless fixture also verified that generated authentication-file names are excluded from Git and Cloud Build upload. No device-token value was retrieved, printed or committed during this setup, and no paid research request was made. Authenticated sync was not rechecked as part of this deployment.
