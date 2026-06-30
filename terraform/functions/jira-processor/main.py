"""
Cloud Function: jira-processor

Triggered by Eventarc when a JSON file lands in the Jira raw GCS bucket.
Loads raw Jira event data into BigQuery for reporting and analytics.

Tables:
  - jira_raw.issue_events      — every Jira event (append-only)
  - jira_curated.issue_current — latest state per issue (upsert via MERGE)
  - jira_curated.issue_history — status change history (append)
"""

import json
import os
import uuid
from datetime import datetime, timezone

import functions_framework
from google.cloud import bigquery, storage

PROJECT_ID = os.environ.get("PROJECT_ID", "")
BQ_RAW_DATASET = os.environ.get("BQ_RAW_DATASET", "jira_raw")
BQ_CURATED_DATASET = os.environ.get("BQ_CURATED_DATASET", "jira_curated")


def read_gcs_json(bucket_name: str, object_name: str) -> dict:
    """Download and parse a JSON file from GCS."""
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    return json.loads(blob.download_as_text())


def insert_raw_event(bq_client: bigquery.Client, payload: dict, gcs_uri: str) -> str:
    """Insert raw Jira event into jira_raw.issue_events. Returns event_id."""
    event_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    row = {
        "event_id": event_id,
        "issue_key": payload.get("issueKey") or payload.get("ticket_id") or "",
        "project_key": payload.get("projectKey") or _extract_project(payload),
        "event_type": payload.get("eventType") or payload.get("event") or "",
        "status": payload.get("status") or "",
        "summary": payload.get("summary") or "",
        "reporter_email": payload.get("reporter_email") or payload.get("reporterEmail") or "",
        "reporter_display_name": payload.get("reporter_display_name") or "",
        "first_name": payload.get("first_name") or payload.get("firstName") or "",
        "group_name": payload.get("group_name") or payload.get("groupName") or "",
        "approvers": payload.get("approvers") or "",
        "raw_payload": json.dumps(payload),
        "gcs_uri": gcs_uri,
        "ingested_at": now,
        "created": payload.get("created") or now,
        "updated": payload.get("updated") or now,
    }

    table_ref = f"{PROJECT_ID}.{BQ_RAW_DATASET}.issue_events"
    errors = bq_client.insert_rows_json(table_ref, [row])
    if errors:
        print(f"[BQ-RAW] Insert errors: {errors}")
        raise RuntimeError(f"BigQuery insert failed: {errors}")

    print(f"[BQ-RAW] Inserted event {event_id} for {row['issue_key']}")
    return event_id


def upsert_current_issue(bq_client: bigquery.Client, payload: dict, event_id: str):
    """Upsert into jira_curated.issue_current using MERGE DML."""
    issue_key = payload.get("issueKey") or payload.get("ticket_id") or ""
    project_key = payload.get("projectKey") or _extract_project(payload)
    now = datetime.now(timezone.utc).isoformat()

    query = f"""
    MERGE `{PROJECT_ID}.{BQ_CURATED_DATASET}.issue_current` AS target
    USING (SELECT @issue_key AS issue_key) AS source
    ON target.issue_key = source.issue_key
    WHEN MATCHED THEN
      UPDATE SET
        status = @status,
        summary = @summary,
        reporter_email = @reporter_email,
        group_name = @group_name,
        approvers = @approvers,
        last_event_type = @event_type,
        updated = @updated,
        last_synced_at = @last_synced_at
    WHEN NOT MATCHED THEN
      INSERT (issue_key, project_key, status, summary, reporter_email,
              group_name, approvers, last_event_type, created, updated, last_synced_at)
      VALUES (@issue_key, @project_key, @status, @summary, @reporter_email,
              @group_name, @approvers, @event_type, @created, @updated, @last_synced_at)
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("issue_key", "STRING", issue_key),
            bigquery.ScalarQueryParameter("project_key", "STRING", project_key),
            bigquery.ScalarQueryParameter("status", "STRING", payload.get("status") or ""),
            bigquery.ScalarQueryParameter("summary", "STRING", payload.get("summary") or ""),
            bigquery.ScalarQueryParameter("reporter_email", "STRING",
                                          payload.get("reporter_email") or payload.get("reporterEmail") or ""),
            bigquery.ScalarQueryParameter("group_name", "STRING",
                                          payload.get("group_name") or payload.get("groupName") or ""),
            bigquery.ScalarQueryParameter("approvers", "STRING", payload.get("approvers") or ""),
            bigquery.ScalarQueryParameter("event_type", "STRING",
                                          payload.get("eventType") or payload.get("event") or ""),
            bigquery.ScalarQueryParameter("created", "STRING", payload.get("created") or now),
            bigquery.ScalarQueryParameter("updated", "STRING", payload.get("updated") or now),
            bigquery.ScalarQueryParameter("last_synced_at", "STRING", now),
        ]
    )

    bq_client.query(query, job_config=job_config).result()
    print(f"[BQ-CURATED] Upserted issue_current for {issue_key}")


def append_history(bq_client: bigquery.Client, payload: dict, event_id: str):
    """Append a row to jira_curated.issue_history."""
    issue_key = payload.get("issueKey") or payload.get("ticket_id") or ""
    now = datetime.now(timezone.utc).isoformat()

    row = {
        "history_id": str(uuid.uuid4()),
        "issue_key": issue_key,
        "event_type": payload.get("eventType") or payload.get("event") or "",
        "new_status": payload.get("status") or "",
        "changed_at": now,
        "raw_event_id": event_id,
    }

    table_ref = f"{PROJECT_ID}.{BQ_CURATED_DATASET}.issue_history"
    errors = bq_client.insert_rows_json(table_ref, [row])
    if errors:
        print(f"[BQ-HISTORY] Insert errors: {errors}")
        raise RuntimeError(f"BigQuery insert failed: {errors}")

    print(f"[BQ-HISTORY] Appended history for {issue_key}")


def _extract_project(payload: dict) -> str:
    """Extract project key from ticket_id like 'NOAA-4' -> 'NOAA'."""
    ticket_id = payload.get("ticket_id", "")
    if "-" in ticket_id:
        return ticket_id.rsplit("-", 1)[0]
    return ""


@functions_framework.cloud_event
def process_jira_event(cloud_event):
    """
    Main entry point. Triggered by Eventarc on GCS object.finalize
    in the Jira raw bucket.
    """
    data = cloud_event.data
    bucket_name = data["bucket"]
    object_name = data["name"]

    # Only process JSON files in the jira/raw/ prefix
    if not object_name.startswith("jira/raw/"):
        print(f"[SKIP] Ignoring non-raw file: {object_name}")
        return "Skipped", 200

    if not object_name.endswith(".json"):
        print(f"[SKIP] Ignoring non-JSON file: {object_name}")
        return "Skipped", 200

    gcs_uri = f"gs://{bucket_name}/{object_name}"
    print(f"[START] Processing Jira event: {gcs_uri}")

    # Read the raw JSON
    payload = read_gcs_json(bucket_name, object_name)

    issue_key = payload.get("issueKey") or payload.get("ticket_id") or "unknown"
    print(f"[JIRA] Issue: {issue_key}, Event: {payload.get('eventType') or payload.get('event')}")

    # Load into BigQuery
    bq_client = bigquery.Client(project=PROJECT_ID)

    # 1. Insert raw event
    event_id = insert_raw_event(bq_client, payload, gcs_uri)

    # 2. Upsert current state
    upsert_current_issue(bq_client, payload, event_id)

    # 3. Append history
    append_history(bq_client, payload, event_id)

    print(f"[DONE] Processed {issue_key} → BQ event_id={event_id}")
    return "OK", 200
