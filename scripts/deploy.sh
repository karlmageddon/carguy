#!/usr/bin/env bash
# Run from the repository root in an authenticated Google Cloud SDK shell.
set -euo pipefail
project=orakle-1792087003
region=us-west1
service=carguy-api
: "${CARGUY_DEVICE_SECRET:?Set CARGUY_DEVICE_SECRET to a Secret Manager secret name containing the device token (not its value)}"
command -v gcloud >/dev/null
# Inspect the existing service; never replace its identity or IAM policy blindly.
service_account=$(gcloud run services describe "$service" --project "$project" --region "$region" --format='value(spec.template.spec.serviceAccountName)')
if [ -z "$service_account" ]; then
  echo 'The service must have an explicit runtime service account. Set one before deploying.' >&2
  exit 1
fi
gcloud firestore databases describe --project "$project" --database=carguy --format='value(name)'
gcloud secrets describe carguy-openai-key --project "$project" --format='value(name)'
gcloud secrets describe "$CARGUY_DEVICE_SECRET" --project "$project" --format='value(name)'
# Grant only the runtime account access to the two required secrets.
for secret_name in carguy-openai-key "$CARGUY_DEVICE_SECRET"; do
  gcloud secrets add-iam-policy-binding "$secret_name" --project "$project" \
    --member="serviceAccount:$service_account" --role=roles/secretmanager.secretAccessor --quiet >/dev/null
done
# Firestore's runtime account also needs roles/datastore.user; see docs/DEPLOYMENT.md.
repository=carguy
if ! gcloud artifacts repositories describe "$repository" --project "$project" --location "$region" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$repository" --project "$project" --location "$region" --repository-format=docker
fi
image="$region-docker.pkg.dev/$project/$repository/api:$(git rev-parse --short=12 HEAD)"
gcloud builds submit . --project "$project" --region "$region" --config cloudbuild.yaml --substitutions="_IMAGE=$image"
# Update just the named settings; retain other settings and existing service IAM.
gcloud run services update "$service" --project "$project" --region "$region" --image "$image" \
  --update-env-vars="CARGUY_ENV=production,CARGUY_STORE=firestore,CARGUY_PROJECT_ID=$project,CARGUY_FIRESTORE_DATABASE=carguy" \
  --update-secrets="CARGUY_RESEARCH_API_KEY=carguy-openai-key:latest,CARGUY_DEVICE_TOKEN=$CARGUY_DEVICE_SECRET:latest" \
  --timeout=300 --quiet
gcloud run services describe "$service" --project "$project" --region "$region" --format='value(status.url)'
