"""
Cloud Function: process-request

Pre-processor that sits between GCS upload and Cloud Run.
Triggered by Eventarc when a JSON file lands in /requests/.

User only provides software selection in JSON. The function automatically
detects WHO uploaded the file via GCS Cloud Audit Logs.

Responsibilities:
  1. Auto-detect uploader (name/email) from Cloud Audit Logs
  2. Read the uploaded JSON request (software only)
  3. Log audit metadata to /audit/ in the same bucket
  4. Compute a software fingerprint (hash of enabled software)
  5. Check if an image with that fingerprint already exists
  6. If duplicate → write status, notify user, skip Cloud Run
  7. If new → enrich JSON with requester info, trigger Cloud Run job
"""

import hashlib
import json
import os
from datetime import datetime, timezone

import functions_framework
from google.cloud import compute_v1, logging as cloud_logging, run_v2, storage


PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION", "us-east4")
BUCKET_NAME = os.environ.get("BUCKET_NAME")
CLOUD_RUN_JOB = os.environ.get("BUILDER_JOB_NAME", "windows-image-builder")

# All valid software keys (must match docker-entrypoint.sh / ansible playbooks)
VALID_SOFTWARE_KEYS = {
    "chrome", "git", "python", "jupyterlab", "conda", "anaconda",
    "rstudio", "rstudio_pro", "pycharm_community", "visual_studio_community",
    "powershell_core", "positron", "paraview", "echoview", "echosms",
    "echostack", "matlab", "gpu_drivers", "oracle_client", "aalibrary",
    "gcp_utilities", "excel",
}

# Map client-friendly software display names to internal keys
CLIENT_SOFTWARE_MAP = {
    "firefox": "chrome",  # browser category
    "chrome": "chrome",
    "google chrome": "chrome",
    "git": "git",
    "github desktop": "git",
    "python": "python",
    "jupyterlab": "jupyterlab",
    "jupyter": "jupyterlab",
    "conda": "conda",
    "miniconda": "conda",
    "anaconda": "anaconda",
    "rstudio": "rstudio",
    "rstudio pro": "rstudio_pro",
    "pycharm": "pycharm_community",
    "pycharm community": "pycharm_community",
    "visual studio": "visual_studio_community",
    "visual studio community": "visual_studio_community",
    "vs code": "visual_studio_community",
    "powershell": "powershell_core",
    "powershell core": "powershell_core",
    "positron": "positron",
    "paraview": "paraview",
    "echoview": "echoview",
    "echosms": "echosms",
    "echostack": "echostack",
    "matlab": "matlab",
    "gpu drivers": "gpu_drivers",
    "nvidia drivers": "gpu_drivers",
    "oracle client": "oracle_client",
    "oracle drivers": "oracle_client",
    "oracle": "oracle_client",
    "aalibrary": "aalibrary",
    "aa library": "aalibrary",
    "gcp utilities": "gcp_utilities",
    "gcloud sdk": "gcp_utilities",
    "gcloud": "gcp_utilities",
    "excel": "excel",
    "microsoft excel": "excel",
}

# Map workstation size strings to GCP machine types + disk size
# Client sends: "Large - (16 – 32 vCPU | RAM: 64 – 128 GB | Storage: 500GB – 1TB)"
WORKSTATION_SIZE_MAP = {
    "small": {"machine_type": "e2-standard-4", "disk_size_gb": 250},
    "medium": {"machine_type": "e2-standard-8", "disk_size_gb": 250},
    "large": {"machine_type": "e2-standard-16", "disk_size_gb": 500},
    "xlarge": {"machine_type": "e2-standard-32", "disk_size_gb": 1000},
    "x-large": {"machine_type": "e2-standard-32", "disk_size_gb": 1000},
}


def normalize_client_json(data: dict) -> dict:
    """
    Detect and normalize client's flat JSON format to our nested format.
    Client format has: software_packages, workstation_size, submitter_name, etc.
    Our format has: image_config.software, requester.name, etc.

    Returns the normalized dict if client format detected, original dict otherwise.
    """
    # Detect client format: has software_packages but no image_config
    if "image_config" in data or "software_packages" not in data:
        return data

    print("[NORMALIZE] Detected client JSON format — converting to pipeline format")

    # Parse software_packages (comma-separated string)
    software = {}
    raw_packages = data.get("software_packages", "")
    if isinstance(raw_packages, str) and raw_packages.strip():
        for pkg in raw_packages.split(","):
            pkg_clean = pkg.strip().lower()
            matched_key = CLIENT_SOFTWARE_MAP.get(pkg_clean)
            if matched_key:
                software[matched_key] = True
                print(f"[NORMALIZE] Mapped '{pkg.strip()}' → {matched_key}")
            else:
                print(f"[NORMALIZE] Unknown software '{pkg.strip()}' — skipped")

    # Fill all software keys with defaults
    full_software = {k: software.get(k, False) for k in sorted(VALID_SOFTWARE_KEYS)}

    # Parse workstation_size to machine_type + disk_size
    ws_size = data.get("workstation_size", "")
    machine_type = "e2-standard-8"  # default medium
    disk_size_gb = 250  # default
    for size_key, spec in WORKSTATION_SIZE_MAP.items():
        if size_key in ws_size.lower():
            machine_type = spec["machine_type"]
            disk_size_gb = spec["disk_size_gb"]
            break
    print(f"[NORMALIZE] Workstation size '{ws_size}' → machine_type={machine_type}, disk={disk_size_gb}GB")

    # Build enabled software list for naming
    enabled = sorted(k for k, v in full_software.items() if v)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    sw_names = [k.replace("_", "") for k in enabled[:5]]
    sw_part = "-".join(sw_names) if sw_names else "custom"
    image_name = f"nmfs-windows-2022-{sw_part}-{ts}"
    image_family = f"nmfs-windows-2022-{sw_part}"

    normalized = {
        "image_config": {
            "image_name": image_name,
            "image_family": image_family,
            "create_vm": True,
            "keep_image": True,
            "software": full_software,
            "machine_type": machine_type,
            "disk_size_gb": disk_size_gb,
        },
        "requester": {
            "name": data.get("submitter_name", "unknown"),
            "email": data.get("submitter_email", "unknown"),
            "team": data.get("fmc", "unknown"),
        },
        "jira_metadata": {
            "ticket_id": data.get("ticket_number", ""),
            "project_key": data.get("ticket_number", "").rsplit("-", 1)[0] if "-" in data.get("ticket_number", "") else "",
            "event_type": data.get("request_type", ""),
            "status": data.get("status", ""),
            "summary": data.get("summary", ""),
            "source": "client-bucket-workflow",
        },
        "requested_at": data.get("created", datetime.now(timezone.utc).isoformat()),
        "additional_unlisted_software": data.get("additional_unlisted_software", ""),
    }

    print(f"[NORMALIZE] Converted: requester={normalized['requester']['name']}, "
          f"software={', '.join(enabled)}, machine_type={machine_type}")

    return normalized


def detect_uploader(bucket_name: str, object_name: str) -> dict:
    """
    Auto-detect who uploaded the file by querying GCS Cloud Audit Logs.
    Returns: { "name": "...", "email": "...", "team": "auto-detected" }
    """
    try:
        logging_client = cloud_logging.Client(project=PROJECT_ID)

        # Query audit logs for this specific GCS object creation
        filter_str = (
            f'resource.type="gcs_bucket" '
            f'resource.labels.bucket_name="{bucket_name}" '
            f'protoPayload.methodName="storage.objects.create" '
            f'protoPayload.resourceName="projects/_/buckets/{bucket_name}/objects/{object_name}" '
            f'severity="NOTICE" '
            f'timestamp>="{(datetime.now(timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")}"'
        )

        # Look at recent entries (last 5 minutes)
        entries = list(logging_client.list_entries(
            filter_=filter_str,
            order_by=cloud_logging.DESCENDING,
            max_results=5,
        ))

        if entries:
            for entry in entries:
                payload = entry.payload if hasattr(entry, 'payload') else {}
                proto = entry.proto_payload if hasattr(entry, 'proto_payload') else None

                # Try to get the caller identity
                if proto and hasattr(proto, 'authentication_info'):
                    email = proto.authentication_info.principal_email
                    if email:
                        # Extract name from email (part before @)
                        name = email.split("@")[0].replace(".", " ").title()
                        print(f"[DETECT] Uploader detected from audit log: {name} <{email}>")
                        return {"name": name, "email": email, "team": "auto-detected"}

        print("[DETECT] Could not find uploader in audit logs — trying object metadata")

    except Exception as e:
        print(f"[DETECT] Audit log query failed: {e}")

    # Fallback: check GCS object metadata (custom metadata set by uploader)
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        blob.reload()

        if blob.metadata:
            email = blob.metadata.get("uploaded-by", blob.metadata.get("email", ""))
            name = blob.metadata.get("uploader-name", blob.metadata.get("name", ""))
            if email:
                if not name:
                    name = email.split("@")[0].replace(".", " ").title()
                print(f"[DETECT] Uploader detected from object metadata: {name} <{email}>")
                return {"name": name, "email": email, "team": "auto-detected"}

        # Last fallback: use the object owner
        if blob.owner and "entity" in blob.owner:
            entity = blob.owner["entity"]
            if "user-" in entity:
                email = entity.replace("user-", "")
                name = email.split("@")[0].replace(".", " ").title()
                print(f"[DETECT] Uploader detected from object owner: {name} <{email}>")
                return {"name": name, "email": email, "team": "auto-detected"}

    except Exception as e:
        print(f"[DETECT] Object metadata check failed: {e}")

    print("[DETECT] Could not auto-detect uploader")
    return {"name": "unknown", "email": "unknown", "team": "unknown"}


def compute_software_fingerprint(software: dict) -> str:
    """
    Create a deterministic hash of the enabled software combination.
    Only includes keys with truthy values, sorted alphabetically.
    """
    enabled = sorted(
        k for k, v in software.items()
        if v is True or str(v).lower() in ("true", "1", "yes")
    )
    fingerprint_str = ",".join(enabled)
    return hashlib.sha256(fingerprint_str.encode()).hexdigest()[:16]


def find_existing_image(fingerprint: str) -> dict | None:
    """
    Check if a GCP image with this software fingerprint label exists.
    Returns image info dict if found, None otherwise.
    """
    client = compute_v1.ImagesClient()
    request = compute_v1.ListImagesRequest(
        project=PROJECT_ID,
        filter=f'labels.software-fingerprint="{fingerprint}" AND deprecated.state!="DELETED"',
        max_results=5,
    )

    for image in client.list(request=request):
        if not image.deprecated or image.deprecated.state == "":
            return {
                "name": image.name,
                "family": image.family,
                "creation_timestamp": image.creation_timestamp,
                "self_link": image.self_link,
            }
        if image.deprecated.state == "DEPRECATED":
            return {
                "name": image.name,
                "family": image.family,
                "creation_timestamp": image.creation_timestamp,
                "self_link": image.self_link,
                "status": "DEPRECATED",
            }
    return None


def write_audit_log(bucket_name: str, request_data: dict, fingerprint: str, action: str):
    """
    Write an audit entry to /audit/ in the GCS bucket.
    Every request gets a permanent record regardless of outcome.
    """
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)

    request_id = request_data.get("request_id", "unknown")
    now = datetime.now(timezone.utc).isoformat()

    requester = request_data.get("requester", {})
    software = request_data.get("image_config", {}).get("software", {})
    enabled_software = sorted(
        k for k, v in software.items()
        if v is True or str(v).lower() in ("true", "1", "yes")
    )

    audit_entry = {
        "request_id": request_id,
        "timestamp": now,
        "requester": {
            "name": requester.get("name", "unknown"),
            "email": requester.get("email", "unknown"),
            "team": requester.get("team", "unknown"),
        },
        "software_requested": enabled_software,
        "software_fingerprint": fingerprint,
        "image_config_name": request_data.get("image_config", {}).get("image_name", ""),
        "create_vm": request_data.get("image_config", {}).get("create_vm", False),
        "action": action,
    }

    blob_name = f"audit/{request_id}_{now.replace(':', '-')}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(json.dumps(audit_entry, indent=2), content_type="application/json")
    print(f"[AUDIT] Written to gs://{bucket_name}/{blob_name}")
    return audit_entry


def write_status(bucket_name: str, request_data: dict, status: str, message: str, image_name: str = ""):
    """Write status JSON to /status/ in the bucket."""
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)

    request_id = request_data.get("request_id", "unknown")
    requester = request_data.get("requester", {})
    now = datetime.now(timezone.utc).isoformat()

    status_data = {
        "request_id": request_id,
        "status": status,
        "requester": {
            "name": requester.get("name", "unknown"),
            "email": requester.get("email", "unknown"),
            "team": requester.get("team", "unknown"),
        },
        "requested_at": request_data.get("requested_at", now),
        "updated_at": now,
        "config": {
            "image_family": request_data.get("image_config", {}).get("image_name", ""),
            "project_id": PROJECT_ID,
            "create_vm": request_data.get("image_config", {}).get("create_vm", False),
            "software": request_data.get("image_config", {}).get("software", {}),
        },
        "result": {
            "image_name": image_name,
            "vm_name": "none",
        },
        "message": message,
    }

    blob = bucket.blob(f"status/{request_id}.json")
    blob.upload_from_string(json.dumps(status_data, indent=2), content_type="application/json")
    print(f"[STATUS] {status} → gs://{bucket_name}/status/{request_id}.json")


def trigger_cloud_run_job(request_json_gcs: str):
    """Trigger the Cloud Run job with REQUEST_JSON_GCS override."""
    client = run_v2.JobsClient()

    job_name = f"projects/{PROJECT_ID}/locations/{REGION}/jobs/{CLOUD_RUN_JOB}"

    override = run_v2.RunJobRequest.Overrides(
        container_overrides=[
            run_v2.RunJobRequest.Overrides.ContainerOverride(
                name="windows-packer-builder",
                env=[
                    run_v2.EnvVar(name="REQUEST_JSON_GCS", value=request_json_gcs),
                ],
            )
        ]
    )

    request = run_v2.RunJobRequest(name=job_name, overrides=override)
    operation = client.run_job(request=request)

    print(f"[CLOUD RUN] Triggered job: {CLOUD_RUN_JOB}")
    print(f"[CLOUD RUN] Execution: {operation.metadata}")
    return operation


@functions_framework.cloud_event
def process_request(cloud_event):
    """
    Main entry point. Triggered by Eventarc on GCS object.finalize.
    """
    data = cloud_event.data
    bucket_name = data["bucket"]
    object_name = data["name"]

    # Only process files in the requests/ prefix
    if not object_name.startswith("requests/"):
        print(f"[SKIP] Ignoring non-request file: {object_name}")
        return "Skipped", 200

    if not object_name.endswith(".json"):
        print(f"[SKIP] Ignoring non-JSON file: {object_name}")
        return "Skipped", 200

    # ── Guard: skip if already processed (prevents recursive trigger) ────
    storage_client_check = storage.Client()
    bucket_check = storage_client_check.bucket(bucket_name)
    blob_check = bucket_check.blob(object_name)
    raw = json.loads(blob_check.download_as_text())
    if raw.get("_processed"):
        print(f"[SKIP] Already processed (recursive trigger blocked): {object_name}")
        return "Already processed", 200

    print(f"[START] Processing request: gs://{bucket_name}/{object_name}")

    # ── 1. Read the JSON request ──────────────────────────────────────────
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    request_data = json.loads(blob.download_as_text())

    # ── 1b. Normalize client JSON format if detected ─────────────────────
    request_data = normalize_client_json(request_data)

    # ── 2. Auto-detect who uploaded the file ──────────────────────────────
    # User does NOT need to put name/email in JSON — we detect automatically
    if "requester" not in request_data or not request_data["requester"].get("email"):
        detected = detect_uploader(bucket_name, object_name)
        request_data["requester"] = detected
        print(f"[AUTO-DETECT] Requester: {detected['name']} <{detected['email']}>")
    else:
        print(f"[JSON] Requester provided in JSON: {request_data['requester']}")

    requester = request_data["requester"]
    requester_name = requester.get("name", "unknown")
    requester_email = requester.get("email", "unknown")

    # ── 3. Auto-generate request_id ───────────────────────────────────────
    request_id = request_data.get("request_id", "")
    if not request_id:
        ts = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
        hash_suffix = hashlib.md5(f"{object_name}{requester_email}".encode()).hexdigest()[:6]
        request_id = f"req-{ts}-{hash_suffix}"
        request_data["request_id"] = request_id

    # Set requested_at timestamp
    if "requested_at" not in request_data:
        request_data["requested_at"] = datetime.now(timezone.utc).isoformat()

    software = request_data.get("image_config", {}).get("software", {})
    enabled_software = sorted(
        k for k, v in software.items()
        if v is True or str(v).lower() in ("true", "1", "yes")
    )

    print(f"[REQUEST] ID: {request_id}")
    print(f"[REQUEST] Requester: {requester_name} <{requester_email}>")
    print(f"[REQUEST] Software: {', '.join(enabled_software)}")

    # ── 4. Compute software fingerprint ───────────────────────────────────
    fingerprint = compute_software_fingerprint(software)
    print(f"[FINGERPRINT] {fingerprint} ({', '.join(enabled_software)})")

    # ── 5. Check for existing image with same fingerprint ─────────────────
    existing_image = find_existing_image(fingerprint)

    if existing_image:
        image_name = existing_image["name"]
        image_family = existing_image.get("family", "")
        created_at = existing_image.get("creation_timestamp", "")

        print(f"[DUPLICATE] Image already exists: {image_name} (created: {created_at})")

        # Write audit log
        write_audit_log(bucket_name, request_data, fingerprint, action="DUPLICATE_FOUND")

        create_vm = request_data.get("image_config", {}).get("create_vm", False)
        if create_vm:
            # Image exists but VM still needs to be created — trigger Cloud Run with existing image
            print(f"[DUPLICATE] Image exists but create_vm=true — triggering VM creation")
            request_data["image_config"]["image_name"] = image_name
            request_data["image_config"]["skip_build"] = True
            request_data["_processed"] = True

            processed_name = object_name.replace("requests/", "processed/")
            processed_blob = storage.Client().bucket(bucket_name).blob(processed_name)
            processed_blob.upload_from_string(
                json.dumps(request_data, indent=2), content_type="application/json"
            )
            print(f"[ENRICH] Written enriched JSON to gs://{bucket_name}/{processed_name}")

            # Mark original as processed to block re-triggers
            orig_blob = storage.Client().bucket(bucket_name).blob(object_name)
            orig_blob.upload_from_string(
                json.dumps(request_data, indent=2), content_type="application/json"
            )
            print(f"[ENRICH] Marked original as processed")

            trigger_cloud_run_job(f"gs://{bucket_name}/{processed_name}")

            message = (
                f"Image '{image_name}' already exists — skipping build, creating VM with "
                f"machine type from request."
            )
            write_status(bucket_name, request_data, "VM_CREATION", message, image_name=image_name)
            return "Duplicate image — VM creation triggered", 200

        # No VM needed — just report duplicate
        message = (
            f"Hi {requester_name}, an image with the exact same software combination "
            f"already exists: '{image_name}' (family: {image_family}). "
            f"No new build is needed. You can use this existing image directly."
        )
        write_status(bucket_name, request_data, "DUPLICATE", message, image_name=image_name)

        return "Duplicate detected — skipped build", 200

    # ── 6. No duplicate — enrich JSON and trigger build ───────────────────
    print(f"[NEW] No existing image with fingerprint {fingerprint} — triggering build")

    # Mark as processed to prevent recursive triggers
    request_data["_processed"] = True

    # Write enriched JSON to /processed/ (not /requests/) for Cloud Run to read
    processed_name = object_name.replace("requests/", "processed/", 1)
    enriched_blob = bucket.blob(processed_name)
    enriched_blob.upload_from_string(
        json.dumps(request_data, indent=2),
        content_type="application/json",
    )
    print(f"[ENRICH] Written enriched JSON to gs://{bucket_name}/{processed_name}")

    # Also mark the original as processed so re-triggers are blocked
    original_blob = bucket.blob(object_name)
    original_data = request_data.copy()
    original_blob.upload_from_string(
        json.dumps(original_data, indent=2),
        content_type="application/json",
    )
    print(f"[ENRICH] Marked original as processed")

    # Write audit log
    write_audit_log(bucket_name, request_data, fingerprint, action="BUILD_TRIGGERED")

    # Write initial status
    write_status(
        bucket_name, request_data, "QUEUED",
        f"Build queued for {requester_name}. Software: {', '.join(enabled_software)}",
    )

    # Trigger Cloud Run job with the enriched JSON path
    request_json_gcs = f"gs://{bucket_name}/{processed_name}"
    trigger_cloud_run_job(request_json_gcs)

    return "Build triggered", 200
