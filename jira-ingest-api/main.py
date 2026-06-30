"""
Cloud Run Service: jira-ingest-api

Receives Jira Automation webhook POSTs, validates the payload,
writes raw JSON to a GCS raw bucket, transforms to image_config format,
and writes to the existing image-builder-requests bucket to trigger
the build pipeline.

Endpoints:
  POST /webhook/jira  — Jira Automation webhook receiver
  GET  /health        — Health check
"""

import json
import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI, Header, HTTPException, Request
from google.cloud import secretmanager, storage

from transform import transform_jira_to_image_config, normalize_jira_payload

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Jira Ingest API", version="1.0.0")

# ── Configuration ────────────────────────────────────────────────────────────
PROJECT_ID = os.environ.get("PROJECT_ID", "")
REGION = os.environ.get("REGION", "us-east4")
RAW_BUCKET = os.environ.get("RAW_BUCKET", "nmfs-winde-jira-raw-dev")
REQUEST_BUCKET = os.environ.get("REQUEST_BUCKET", "")
WEBHOOK_SECRET_NAME = os.environ.get("WEBHOOK_SECRET_NAME", "jira-webhook-secret")

# Cache the webhook secret to avoid repeated Secret Manager calls
_cached_secret = None


def get_webhook_secret() -> str:
    """Fetch the webhook secret from Secret Manager (cached)."""
    global _cached_secret
    if _cached_secret:
        return _cached_secret

    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{WEBHOOK_SECRET_NAME}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    _cached_secret = response.payload.data.decode("UTF-8").strip()
    return _cached_secret


def validate_webhook_secret(secret_header: str | None):
    """Validate the X-Jira-Secret header against the stored secret."""
    if not secret_header:
        raise HTTPException(status_code=401, detail="Missing X-Jira-Secret header")

    expected = get_webhook_secret()
    if secret_header != expected:
        raise HTTPException(status_code=401, detail="Invalid webhook secret")


# ── Required fields ──────────────────────────────────────────────────────────
# At minimum we need an issue key and an event type
REQUIRED_FIELDS = {"issue_key", "event_type"}


def validate_payload(normalized: dict):
    """Check that required fields are present after normalization."""
    missing = [f for f in REQUIRED_FIELDS if not normalized.get(f)]
    if missing:
        raise HTTPException(
            status_code=400,
            detail=f"Missing required fields: {', '.join(missing)}. "
            f"Provide 'ticket_id'/'issueKey' and 'event'/'eventType'.",
        )


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "service": "jira-ingest-api"}


@app.post("/webhook/jira")
async def webhook_jira(
    request: Request,
    x_jira_secret: str | None = Header(None),
):
    """
    Receive Jira Automation webhook, validate, store raw + transform.

    Flow:
      1. Validate webhook secret
      2. Parse and validate required fields
      3. Write raw JSON to gs://RAW_BUCKET/jira/raw/...
      4. Transform to image_config format
      5. Write to gs://REQUEST_BUCKET/requests/jira-{issueKey}-{ts}.json
      6. Return success with paths
    """
    # 1. Auth
    validate_webhook_secret(x_jira_secret)

    # 2. Parse body
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    logger.info(f"[WEBHOOK] Received Jira payload: {json.dumps(payload)[:500]}")

    # Normalize field names
    normalized = normalize_jira_payload(payload)
    validate_payload(normalized)

    issue_key = normalized["issue_key"]
    project_key = normalized["project_key"]
    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    ts = now.strftime("%Y%m%d%H%M%S")

    # 3. Write raw JSON to raw bucket
    storage_client = storage.Client()

    raw_path = f"jira/raw/project_key={project_key}/date={date_str}/issue-{issue_key}.json"
    raw_bucket = storage_client.bucket(RAW_BUCKET)
    raw_blob = raw_bucket.blob(raw_path)
    raw_blob.upload_from_string(
        json.dumps(payload, indent=2),
        content_type="application/json",
    )
    logger.info(f"[RAW] Written to gs://{RAW_BUCKET}/{raw_path}")

    # 4. Transform to image_config format
    try:
        image_config = transform_jira_to_image_config(payload)
    except ValueError as e:
        logger.warning(f"[TRANSFORM] Validation failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))

    # 5. Write transformed JSON to request bucket
    request_path = f"requests/jira-{issue_key}-{ts}.json"
    req_bucket = storage_client.bucket(REQUEST_BUCKET)
    req_blob = req_bucket.blob(request_path)
    req_blob.upload_from_string(
        json.dumps(image_config, indent=2),
        content_type="application/json",
    )
    logger.info(f"[REQUEST] Written to gs://{REQUEST_BUCKET}/{request_path}")

    return {
        "status": "accepted",
        "issue_key": issue_key,
        "raw_path": f"gs://{RAW_BUCKET}/{raw_path}",
        "request_path": f"gs://{REQUEST_BUCKET}/{request_path}",
        "message": f"Jira ticket {issue_key} accepted. Image build pipeline triggered.",
    }
