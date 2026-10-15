#!/bin/sh
# Deploys the Prosapia server to Cloud Run and the Firebase Hosting front
# that routes the site's address to it. The one-time setup this relies on
# is in docs/deploying.md.
#
#   tool/deploy.sh
#
# Settings, with their defaults: PROJECT=prosapia-ea818 TREE=carew.
set -eu

PROJECT=${PROJECT:-prosapia-ea818}
TREE=${TREE:-carew}
REGION=us-west1
SERVICE=prosapia

# Cloud Build builds the image from the Dockerfile; Cloud Run runs it as the
# server's own service account, with the Anthropic key from Secret Manager.
gcloud run deploy "$SERVICE" \
  --source . \
  --project "$PROJECT" \
  --region "$REGION" \
  --service-account "prosapia-server@$PROJECT.iam.gserviceaccount.com" \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT,PROSAPIA_TREE=$TREE" \
  --set-secrets "ANTHROPIC_API_KEY=anthropic-api-key:latest" \
  --memory 1Gi \
  --max-instances 2 \
  --allow-unauthenticated

# The nightly export runs from the same image as a Cloud Run job, started
# by Cloud Scheduler (set up once; see docs/deploying.md).
IMAGE=$(gcloud run services describe "$SERVICE" --project "$PROJECT" \
  --region "$REGION" --format 'value(spec.template.spec.containers[0].image)')
gcloud run jobs deploy prosapia-export \
  --image "$IMAGE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --service-account "prosapia-server@$PROJECT.iam.gserviceaccount.com" \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT,PROSAPIA_TREE=$TREE,PROSAPIA_EXPORT_REPO=${EXPORT_REPO:-git@github.com:devoncarew/prosapia-$TREE.git}" \
  --set-secrets "GITHUB_EXPORT_KEY=github-export-key:latest" \
  --command /app/bin/prosapia \
  --args export \
  --memory 2Gi \
  --task-timeout 30m \
  --max-retries 1

# Hosting serves the site's address and forwards every request to Cloud
# Run. It only changes when firebase.json does, but deploying it is cheap.
firebase deploy --only hosting --project "$PROJECT"
