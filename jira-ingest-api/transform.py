"""
Jira payload → image_config format bridge.

Transforms an incoming Jira webhook payload into the image_config JSON
format expected by the existing process-request Cloud Function.
"""

import hashlib
from datetime import datetime, timezone

# All valid software keys (must match sample-request.json / ansible playbooks)
VALID_SOFTWARE_KEYS = {
    "chrome", "git", "python", "jupyterlab", "conda", "anaconda",
    "rstudio", "rstudio_pro", "pycharm_community", "visual_studio_community",
    "powershell_core", "positron", "paraview", "echoview", "echosms",
    "echostack", "matlab", "gpu_drivers", "oracle_client", "aalibrary",
    "gcp_utilities", "excel",
}


def normalize_jira_payload(payload: dict) -> dict:
    """
    Normalize field names from the Jira webhook payload.
    Handles both the client's canonical names (issueKey, projectKey)
    and the sample payload names (ticket_id, event).
    """
    return {
        "issue_key": payload.get("issueKey") or payload.get("ticket_id") or "",
        "project_key": payload.get("projectKey") or _extract_project_key(payload) or "",
        "event_type": payload.get("eventType") or payload.get("event") or "",
        "status": payload.get("status") or "Submitted",
        "summary": payload.get("summary") or "",
        "created": payload.get("created") or datetime.now(timezone.utc).isoformat(),
        "updated": payload.get("updated") or datetime.now(timezone.utc).isoformat(),
        "source_system": payload.get("sourceSystem") or "jira",
        "reporter_email": payload.get("reporter_email") or payload.get("reporterEmail") or "",
        "reporter_display_name": payload.get("reporter_display_name") or payload.get("reporterDisplayName"),
        "first_name": payload.get("first_name") or payload.get("firstName") or "",
        "group_name": payload.get("group_name") or payload.get("groupName") or "",
        "approvers": payload.get("approvers") or "",
    }


def _extract_project_key(payload: dict) -> str:
    """Extract project key from ticket_id like 'NOAA-4' -> 'NOAA'."""
    ticket_id = payload.get("ticket_id", "")
    if "-" in ticket_id:
        return ticket_id.rsplit("-", 1)[0]
    return ""


def extract_software(payload: dict) -> dict:
    """
    Extract software selections from Jira payload.

    Checks these locations in order:
      1. payload["software_selections"] — comma-separated string from Jira checkboxes
      2. payload["software"] — direct dict of {name: bool}
      3. payload["image_config"]["software"] — nested under image_config
      4. Individual install_* fields in the payload root

    Returns a dict with all VALID_SOFTWARE_KEYS, defaulting to False.
    """
    software = {}

    # Map Jira checkbox display names to internal software keys
    DISPLAY_TO_KEY = {
        "chrome": "chrome",
        "git": "git",
        "python": "python",
        "jupyterlab": "jupyterlab",
        "conda": "conda",
        "anaconda": "anaconda",
        "rstudio": "rstudio",
        "rstudio_pro": "rstudio_pro",
        "rstudio pro": "rstudio_pro",
        "pycharm": "pycharm_community",
        "pycharm_community": "pycharm_community",
        "pycharm community": "pycharm_community",
        "visual_studio": "visual_studio_community",
        "visual_studio_community": "visual_studio_community",
        "visual studio community": "visual_studio_community",
        "powershell": "powershell_core",
        "powershell_core": "powershell_core",
        "powershell core": "powershell_core",
        "positron": "positron",
        "paraview": "paraview",
        "echoview": "echoview",
        "echosms": "echosms",
        "echostack": "echostack",
        "matlab": "matlab",
        "gpu_drivers": "gpu_drivers",
        "gpu drivers": "gpu_drivers",
        "oracle_client": "oracle_client",
        "oracle client": "oracle_client",
        "aalibrary": "aalibrary",
        "aa library": "aalibrary",
        "aa-si aalibrary": "aalibrary",
        "gcp_utilities": "gcp_utilities",
        "gcp utilities": "gcp_utilities",
        "excel": "excel",
    }

    # Location 1: Jira checkboxes → comma-separated string (e.g. "Chrome, Git, Python")
    if isinstance(payload.get("software_selections"), str) and payload["software_selections"].strip():
        selected_names = [s.strip().lower() for s in payload["software_selections"].split(",")]
        for name in selected_names:
            matched_key = DISPLAY_TO_KEY.get(name) or DISPLAY_TO_KEY.get(name.replace(" ", "_"))
            if matched_key:
                software[matched_key] = True
    # Location 2: Jira checkboxes → array of objects (e.g. [{"value": "Chrome"}])
    elif isinstance(payload.get("software_selections"), list):
        for item in payload["software_selections"]:
            name = item.get("value", item) if isinstance(item, dict) else str(item)
            name = name.strip().lower()
            matched_key = DISPLAY_TO_KEY.get(name) or DISPLAY_TO_KEY.get(name.replace(" ", "_"))
            if matched_key:
                software[matched_key] = True
    # Location 3: top-level "software" dict
    elif isinstance(payload.get("software"), dict):
        software = payload["software"]
    # Location 4: nested under image_config
    elif isinstance(payload.get("image_config", {}).get("software"), dict):
        software = payload["image_config"]["software"]
    # Location 5: individual install_* fields
    else:
        for key in VALID_SOFTWARE_KEYS:
            install_key = f"install_{key}"
            if install_key in payload:
                software[key] = payload[install_key]

    # Build the full software dict with all keys, defaulting to False
    result = {}
    for key in sorted(VALID_SOFTWARE_KEYS):
        val = software.get(key, False)
        result[key] = _to_bool(val)

    return result


def _to_bool(val) -> bool:
    """Convert various truthy/falsy values to bool."""
    if isinstance(val, bool):
        return val
    if isinstance(val, str):
        return val.lower() in ("true", "1", "yes")
    return bool(val)


def transform_jira_to_image_config(payload: dict) -> dict:
    """
    Main transform: converts Jira webhook payload into the image_config
    format expected by the existing pipeline.

    Returns a dict matching the structure in sample-request.json, plus
    requester and jira_metadata blocks.

    Raises ValueError if no software selections found.
    """
    normalized = normalize_jira_payload(payload)
    software = extract_software(payload)

    # Check that at least one software is enabled
    enabled = [k for k, v in software.items() if v]
    if not enabled:
        raise ValueError(
            "No software selections found in Jira payload. "
            "Expected a 'software' dict with at least one item set to true."
        )

    # Build image name: nmfs-windows-2022-{software}-{timestamp}
    ts = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    # Use short software names joined by hyphens (max 5 to keep name reasonable)
    sw_names = [k.replace("_", "") for k in enabled[:5]]
    sw_part = "-".join(sw_names) if sw_names else "custom"
    image_name = f"nmfs-windows-2022-{sw_part}-{ts}"

    # Determine create_vm and keep_image from payload (defaults: true)
    create_vm = _to_bool(
        payload.get("create_vm", payload.get("image_config", {}).get("create_vm", True))
    )
    keep_image = _to_bool(
        payload.get("keep_image", payload.get("image_config", {}).get("keep_image", True))
    )

    return {
        "image_config": {
            "image_name": image_name,
            "image_family": "nmfs-windows-2022",
            "create_vm": create_vm,
            "keep_image": keep_image,
            "software": software,
        },
        "requester": {
            "name": normalized["first_name"] or normalized["reporter_display_name"] or "unknown",
            "email": normalized["reporter_email"] or "unknown",
            "team": normalized["group_name"] or "unknown",
        },
        "jira_metadata": {
            "ticket_id": normalized["issue_key"],
            "project_key": normalized["project_key"],
            "event_type": normalized["event_type"],
            "status": normalized["status"],
            "summary": normalized["summary"],
            "approvers": normalized["approvers"],
            "source": "jira-ingest-api",
        },
    }
