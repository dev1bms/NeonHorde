#!/bin/bash
# Neon Horde — final-mile release automation (GOAL Phase 11).
# Prerequisite: ~/.appstoreconnect/neonhorde.env (see RELEASE_RUNBOOK.md).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

ENV_FILE="$HOME/.appstoreconnect/neonhorde.env"

# ---- 1. Validate credentials before any expensive step -----------------
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE missing — follow RELEASE_RUNBOOK.md step 2 first." >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a
for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH REVIEW_FIRST_NAME REVIEW_LAST_NAME REVIEW_PHONE REVIEW_EMAIL; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var is not set in $ENV_FILE" >&2
        exit 1
    fi
done
if [ ! -f "$ASC_KEY_PATH" ]; then
    echo "ERROR: .p8 key not found at $ASC_KEY_PATH" >&2
    exit 1
fi

echo "==> Credentials look sane. Smoke-testing App Store Connect API auth…"
# Cheap auth check: list apps via fastlane's Spaceship through a tiny lane.
fastlane run app_store_connect_api_key \
    key_id:"$ASC_KEY_ID" issuer_id:"$ASC_ISSUER_ID" key_filepath:"$ASC_KEY_PATH" >/dev/null \
    || { echo "ERROR: ASC API key rejected"; exit 1; }

# ---- 2. App record check (NOT automatable with an API key) --------------
# The public ASC API cannot create app records; if missing, do it once in
# the web UI (RELEASE_RUNBOOK.md step 3), then re-run this script.
echo "==> Reminder: the app record 'Neon Horde — Arena Survivor'"
echo "    (com.belalalswerki.neonhorde) must exist in App Store Connect."
echo "    If the upload below fails with 'app not found', do runbook step 3."

# ---- 3. Build, upload to TestFlight, then submit with metadata ----------
echo "==> Uploading to TestFlight (fastlane beta)…"
for attempt in 1 2 3; do
    if fastlane beta; then break; fi
    echo "beta attempt $attempt failed — retrying in 60s (cloud-signing hiccups are known)"
    sleep 60
    [ "$attempt" = 3 ] && { echo "ERROR: beta failed 3×"; exit 1; }
done

echo "==> Pushing metadata + screenshots and submitting for review…"
fastlane release

echo "==> DONE. Track review status in App Store Connect."
