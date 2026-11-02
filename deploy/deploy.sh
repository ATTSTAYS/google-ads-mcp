#!/usr/bin/env bash
# Bygger og deployer Google Ads MCP til Cloud Run for Att Stays.
# Kjøres i Cloud Shell med prosjektet att-google-ads valgt.
# Trygt å kjøre flere ganger: hopper over det som finnes fra før.
#
# Bruk:
#   bash deploy/deploy.sh                  bygg og deploy main
#   NEW_SECRET=1 bash deploy/deploy.sh     ber også om ny client secret
set -euo pipefail

PROJECT=nimble-lead-513509-g5
REGION=europe-north1
SERVICE=google-ads-mcp
SA=google-ads-mcp@$PROJECT.iam.gserviceaccount.com
CLIENT_ID=378188152321-gco9itnu0viaul4srplam82hfh2oq6dp.apps.googleusercontent.com
BASE_URL=https://google-ads-mcp-zsawebeycq-lz.a.run.app

gcloud config set project "$PROJECT"
exists() { "$@" >/dev/null 2>&1; }

# 1. Tjenester
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com firestore.googleapis.com

# 2. Firestore (lager for innlogginger)
if exists gcloud firestore databases describe --database="(default)"; then
  echo "Firestore: $(gcloud firestore databases describe --database='(default)' --format='value(locationId,type)')"
else
  gcloud firestore databases create --location=eur3 --type=firestore-native
fi

# 3. Hemmeligheter
if ! exists gcloud secrets describe ads-mcp-oauth-client-secret || [ "${NEW_SECRET:-0}" = "1" ]; then
  read -s -p "Lim inn client secret (én gang) og trykk Enter: " CS; echo
  if [ ${#CS} -ne 35 ]; then echo "Feil lengde (${#CS}, ventet 35). Stopper."; exit 1; fi
  if exists gcloud secrets describe ads-mcp-oauth-client-secret; then
    printf '%s' "$CS" | gcloud secrets versions add ads-mcp-oauth-client-secret --data-file=-
  else
    printf '%s' "$CS" | gcloud secrets create ads-mcp-oauth-client-secret --data-file=-
  fi
  unset CS
fi
exists gcloud secrets describe ads-mcp-jwt-signing-key || \
  openssl rand -hex 32 | tr -d '\n' | gcloud secrets create ads-mcp-jwt-signing-key --data-file=-
exists gcloud secrets describe ads-mcp-storage-encryption-key || \
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' | gcloud secrets create ads-mcp-storage-encryption-key --data-file=-

# 4. Tjenestekonto med minste nødvendige tilgang
if ! exists gcloud iam service-accounts describe "$SA"; then
  gcloud iam service-accounts create google-ads-mcp --display-name="Google Ads MCP"
  sleep 10
fi
gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" \
  --role=roles/datastore.user --condition=None >/dev/null
for S in ads-mcp-oauth-client-secret ads-mcp-jwt-signing-key ads-mcp-storage-encryption-key; do
  gcloud secrets add-iam-policy-binding "$S" --member="serviceAccount:$SA" \
    --role=roles/secretmanager.secretAccessor >/dev/null
done

# 5. Bygg fra main i ATTSTAYS/google-ads-mcp
exists gcloud artifacts repositories describe mcp-servers --location="$REGION" || \
  gcloud artifacts repositories create mcp-servers --repository-format=docker --location="$REGION"
SRC=$(mktemp -d)
git clone --depth 1 https://github.com/ATTSTAYS/google-ads-mcp.git "$SRC"
COMMIT=$(git -C "$SRC" rev-parse --short HEAD)
IMAGE=$REGION-docker.pkg.dev/$PROJECT/mcp-servers/$SERVICE:$COMMIT
gcloud builds submit "$SRC" --region="$REGION" --tag "$IMAGE"
rm -rf "$SRC"

# 6. Drift
gcloud run deploy "$SERVICE" --image "$IMAGE" --region "$REGION" \
  --service-account "$SA" --allow-unauthenticated --min-instances 0 --max-instances 1 \
  --set-env-vars "GOOGLE_PROJECT_ID=$PROJECT,GOOGLE_ADS_MCP_OAUTH_CLIENT_ID=$CLIENT_ID,GOOGLE_ADS_MCP_BASE_URL=$BASE_URL,GOOGLE_ADS_MCP_STORAGE_TYPE=firestore,GOOGLE_ADS_MCP_STORAGE_FIRESTORE_PROJECT=$PROJECT,FASTMCP_HOST=0.0.0.0" \
  --set-secrets "GOOGLE_ADS_MCP_OAUTH_CLIENT_SECRET=ads-mcp-oauth-client-secret:latest,GOOGLE_ADS_MCP_JWT_SIGNING_KEY=ads-mcp-jwt-signing-key:latest,GOOGLE_ADS_MCP_STORAGE_ENCRYPTION_KEY=ads-mcp-storage-encryption-key:latest"

# 7. Sjekk
echo "Commit: $COMMIT"
echo "URL: $BASE_URL/mcp"
curl -s -o /dev/null -w "Uten innlogging: HTTP %{http_code} (skal være 401)\n" -X POST "$BASE_URL/mcp"
