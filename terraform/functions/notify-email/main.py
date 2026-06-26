"""
Cloud Function: image-builder-notify-email

Triggered by Pub/Sub when image build completes/fails.
Sends email notification to the requester using SendGrid.

Pub/Sub message payload:
{
  "request_id": "...",
  "status": "COMPLETED" | "FAILED",
  "requester_name": "...",
  "requester_email": "...",
  "image_name": "...",
  "vm_name": "...",
  "message": "...",
  "project_id": "..."
}
"""

import base64
import json
import os

import functions_framework
from google.cloud import secretmanager
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail


def get_sendgrid_api_key():
    """Fetch SendGrid API key from Secret Manager."""
    secret_name = os.environ.get("SENDGRID_API_KEY_SECRET", "sendgrid-api-key")
    project_id = os.environ.get("PROJECT_ID")
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def build_email_html(data):
    """Build HTML email body from notification data."""
    status = data.get("status", "UNKNOWN")
    requester_name = data.get("requester_name", "User")
    image_name = data.get("image_name", "N/A")
    vm_name = data.get("vm_name", "none")
    message = data.get("message", "")
    request_id = data.get("request_id", "N/A")
    project_id = data.get("project_id", "N/A")

    status_color = "#28a745" if status == "COMPLETED" else "#dc3545"
    status_label = "Successfully Built" if status == "COMPLETED" else "Build Failed"

    vm_section = ""
    if vm_name and vm_name not in ("none", "FAILED", ""):
        vm_section = f"""
        <tr>
          <td style="padding:8px;font-weight:bold;">VM Name</td>
          <td style="padding:8px;">{vm_name}</td>
        </tr>"""
    elif vm_name == "FAILED":
        vm_section = """
        <tr>
          <td style="padding:8px;font-weight:bold;">VM Status</td>
          <td style="padding:8px;color:#dc3545;">VM creation failed — image is still available</td>
        </tr>"""

    return f"""
    <html>
    <body style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">
      <div style="background:{status_color};color:white;padding:20px;text-align:center;">
        <h2>Windows Image Builder — {status_label}</h2>
      </div>
      <div style="padding:20px;">
        <p>Hi {requester_name},</p>
        <p>{message}</p>
        <table style="width:100%;border-collapse:collapse;margin:20px 0;">
          <tr style="background:#f8f9fa;">
            <td style="padding:8px;font-weight:bold;">Request ID</td>
            <td style="padding:8px;">{request_id}</td>
          </tr>
          <tr>
            <td style="padding:8px;font-weight:bold;">Status</td>
            <td style="padding:8px;color:{status_color};font-weight:bold;">{status}</td>
          </tr>
          <tr style="background:#f8f9fa;">
            <td style="padding:8px;font-weight:bold;">Image Name</td>
            <td style="padding:8px;">{image_name}</td>
          </tr>
          {vm_section}
          <tr style="background:#f8f9fa;">
            <td style="padding:8px;font-weight:bold;">Project</td>
            <td style="padding:8px;">{project_id}</td>
          </tr>
        </table>
        <p style="color:#666;font-size:12px;">
          This is an automated notification from the Windows Image Builder pipeline.
        </p>
      </div>
    </body>
    </html>
    """


@functions_framework.cloud_event
def handle_pubsub(cloud_event):
    """Handle Pub/Sub message and send email notification."""
    pubsub_data = base64.b64decode(
        cloud_event.data["message"]["data"]
    ).decode("utf-8")

    data = json.loads(pubsub_data)

    requester_email = data.get("requester_email", "")
    if not requester_email or requester_email == "unknown":
        print(f"No requester email — skipping notification for request {data.get('request_id')}")
        return "No email to send", 200

    status = data.get("status", "UNKNOWN")
    from_email = os.environ.get("FROM_EMAIL", "noreply@example.com")

    subject = f"[Image Builder] {status} — {data.get('image_name', 'N/A')}"

    html_content = build_email_html(data)

    message = Mail(
        from_email=from_email,
        to_emails=requester_email,
        subject=subject,
        html_content=html_content,
    )

    try:
        api_key = get_sendgrid_api_key()
        sg = SendGridAPIClient(api_key)
        response = sg.send(message)
        print(
            f"Email sent to {requester_email} — "
            f"status_code={response.status_code}, request_id={data.get('request_id')}"
        )
    except Exception as e:
        print(f"Failed to send email to {requester_email}: {e}")
        raise

    return "OK", 200
