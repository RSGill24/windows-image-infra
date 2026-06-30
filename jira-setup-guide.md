# Jira Cloud — GUI Setup Guide for Image Builder Integration

This guide walks through every click needed to configure Jira Cloud to trigger the GCP Image Builder pipeline.

**Prerequisites:**
- Jira Cloud admin access (or Project Admin for your project)
- Cloud Run URL: `https://jira-ingest-api-XXXXX-ue.a.run.app` (from `terraform output jira_ingest_api_url`)
- Webhook secret value (from `gcloud secrets versions access latest --secret=jira-webhook-secret`)

---

## Part 1: Create Custom Fields

### 1.1 Navigate to Custom Fields

```
Jira Cloud → ⚙️ Settings (top-right gear icon)
  → Issues → Custom Fields
  → Create custom field (top-right button)
```

### 1.2 Create these fields one by one

Click **"Create custom field"** for each:

| # | Field Name | Field Type | Notes |
|---|-----------|-----------|-------|
| 1 | `First Name` | **Short text** | Requester's first name |
| 2 | `Group Name` | **Select list (single)** | Options: GARFO, SEFSC, NWFSC, SWFSC, NEFSC, PIFSC, AFSC (add your teams) |
| 3 | `Approver Name` | **Short text** | Or use **User picker (single)** if you want Jira user lookup |
| 4 | `Install Chrome` | **Checkbox** | Will send `true`/`false` |
| 5 | `Install Git` | **Checkbox** | |
| 6 | `Install Python` | **Checkbox** | |
| 7 | `Install JupyterLab` | **Checkbox** | |
| 8 | `Install Conda` | **Checkbox** | |
| 9 | `Install Anaconda` | **Checkbox** | |
| 10 | `Install RStudio` | **Checkbox** | |
| 11 | `Install RStudio Pro` | **Checkbox** | |
| 12 | `Install PyCharm` | **Checkbox** | |
| 13 | `Install Visual Studio` | **Checkbox** | |
| 14 | `Install PowerShell` | **Checkbox** | |
| 15 | `Install Positron` | **Checkbox** | |
| 16 | `Install ParaView` | **Checkbox** | |
| 17 | `Install Echoview` | **Checkbox** | |
| 18 | `Install EchoSMs` | **Checkbox** | |
| 19 | `Install EchoStack` | **Checkbox** | |
| 20 | `Install MATLAB` | **Checkbox** | |
| 21 | `Install GPU Drivers` | **Checkbox** | |
| 22 | `Install Oracle Client` | **Checkbox** | |
| 23 | `Install AALibrary` | **Checkbox** | |
| 24 | `Install GCP Utilities` | **Checkbox** | |
| 25 | `Install Excel` | **Checkbox** | |

**For each field:**
1. Click **Create custom field**
2. Select the type (Short text / Select list / Checkbox)
3. Name it exactly as shown
4. Click **Create**
5. On the "Associate to screens" page → select **All screens** (or just your project screens)
6. Click **Update**

### 1.3 Get Custom Field IDs

After creating all fields, you need the internal field IDs for the Automation rule.

**Method 1: Via Jira UI**
```
⚙️ Settings → Issues → Custom Fields
  → Find each field → Click ⋯ (three dots) → Edit Details
  → Look at the URL: .../customfield_10050
  → The number (10050) is the field ID
```

**Method 2: Via Jira REST API (faster)**

Open browser or curl:
```
https://YOUR-ORG.atlassian.net/rest/api/3/field
```

Search the JSON response for your field names. Each will have an `id` like `customfield_10050`.

**Write down all the IDs:**

| Field Name | Field ID (example) | Your Actual ID |
|-----------|-------------------|----------------|
| First Name | `customfield_10050` | `customfield_______` |
| Group Name | `customfield_10051` | `customfield_______` |
| Approver Name | `customfield_10052` | `customfield_______` |
| Install Chrome | `customfield_10060` | `customfield_______` |
| Install Git | `customfield_10061` | `customfield_______` |
| Install Python | `customfield_10062` | `customfield_______` |
| Install JupyterLab | `customfield_10063` | `customfield_______` |
| Install Conda | `customfield_10064` | `customfield_______` |
| Install Anaconda | `customfield_10065` | `customfield_______` |
| Install RStudio | `customfield_10066` | `customfield_______` |
| Install RStudio Pro | `customfield_10067` | `customfield_______` |
| Install PyCharm | `customfield_10068` | `customfield_______` |
| Install Visual Studio | `customfield_10069` | `customfield_______` |
| Install PowerShell | `customfield_10070` | `customfield_______` |
| Install Positron | `customfield_10071` | `customfield_______` |
| Install ParaView | `customfield_10072` | `customfield_______` |
| Install Echoview | `customfield_10073` | `customfield_______` |
| Install EchoSMs | `customfield_10074` | `customfield_______` |
| Install EchoStack | `customfield_10075` | `customfield_______` |
| Install MATLAB | `customfield_10076` | `customfield_______` |
| Install GPU Drivers | `customfield_10077` | `customfield_______` |
| Install Oracle Client | `customfield_10078` | `customfield_______` |
| Install AALibrary | `customfield_10079` | `customfield_______` |
| Install GCP Utilities | `customfield_10080` | `customfield_______` |
| Install Excel | `customfield_10081` | `customfield_______` |

---

## Part 2: Create Issue Type (if not exists)

### 2.1 Create "Workstation Request" issue type

```
⚙️ Settings → Issues → Issue Types
  → Add issue type (top-right)
  → Name: "Workstation Request"
  → Type: Standard
  → Click Add
```

### 2.2 Add custom fields to the issue type screen

```
⚙️ Settings → Issues → Screens
  → Find screen associated with "Workstation Request"
  → Click Configure
  → Add all 25 custom fields created above
```

**Or via Project Settings:**
```
Your Project → ⚙️ Project Settings → Issue Types
  → Click "Workstation Request"
  → Drag & drop fields into the layout:
      - Summary (default, already there)
      - First Name
      - Group Name
      - Approver Name
      - All 22 Install * checkboxes (group them under a section "Software Selection")
```

---

## Part 3: Create Request Type in Jira Service Management (Optional)

If using **Jira Service Management** (customer portal):

### 3.1 Create Request Type

```
Your Project → ⚙️ Project Settings → Request Types
  → Add request type
  → Name: "Workstation Request"
  → Issue Type: Workstation Request (created above)
  → Click Add
```

### 3.2 Configure the form

```
Click on "Workstation Request" request type
  → Edit request form
  → Add fields:
      - Summary
      - First Name
      - Group Name
      - Approver Name
      - All Install * checkboxes
  → Arrange in a logical order
  → Click Save
```

### 3.3 Add to portal

```
⚙️ Project Settings → Portal Settings
  → Portal Groups
  → Add "Workstation Request" to a group (e.g., "IT Requests")
```

---

## Part 4: Create Automation Rule (THE KEY STEP)

This is the rule that fires the webhook to GCP when someone creates a ticket.

### 4.1 Navigate to Automation

```
Your Project → ⚙️ Project Settings → Automation
  → Create rule (top-right)
```

### 4.2 Set the Trigger

```
Click "New trigger"
  → Search: "Issue created"
  → Select: "Issue created"
  → Click: Save
```

### 4.3 Add a Condition (Optional but recommended)

```
Click "+ Add component" → Condition
  → Select: "Issue fields condition"
  → Field: Issue Type
  → Condition: equals
  → Value: Workstation Request
  → Click: Save
```

This ensures only "Workstation Request" tickets trigger the webhook, not every issue.

### 4.4 Add the Web Request Action

```
Click "+ Add component" → Action
  → Search: "Send web request"
  → Select: "Send web request"
```

Fill in:

| Setting | Value |
|---------|-------|
| **Web request URL** | `https://jira-ingest-api-XXXXX-ue.a.run.app/webhook/jira` |
| **HTTP method** | `POST` |
| **Web request body** | `Custom data` |
| **Headers** | (see below) |
| **Body** | (see below) |

#### Headers

Click **"Add header"** twice:

| Header Name | Header Value |
|-------------|-------------|
| `Content-Type` | `application/json` |
| `X-Jira-Secret` | `<paste your webhook secret from Secret Manager>` |

#### Body (Custom Data — JSON)

Paste this JSON, replacing `customfield_XXXXX` with YOUR actual field IDs from Part 1.3:

```json
{
  "event": "jira_workstation_request",
  "eventType": "issue_created",
  "sourceSystem": "jira",
  "ticket_id": "{{issue.key}}",
  "issueKey": "{{issue.key}}",
  "projectKey": "{{issue.project.key}}",
  "status": "{{issue.status.name}}",
  "summary": "{{issue.summary}}",
  "created": "{{issue.created}}",
  "updated": "{{issue.updated}}",
  "reporter_email": "{{issue.reporter.emailAddress}}",
  "reporter_display_name": "{{issue.reporter.displayName}}",
  "first_name": "{{issue.customfield_XXXXX}}",
  "group_name": "{{issue.customfield_XXXXX}}",
  "approvers": "{{issue.customfield_XXXXX}}",
  "software": {
    "chrome": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "git": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "python": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "jupyterlab": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "conda": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "anaconda": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "rstudio": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "rstudio_pro": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "pycharm_community": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "visual_studio_community": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "powershell_core": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "positron": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "paraview": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "echoview": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "echosms": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "echostack": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "matlab": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "gpu_drivers": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "oracle_client": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "aalibrary": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "gcp_utilities": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}},
    "excel": {{#issue.customfield_XXXXX}}true{{/issue.customfield_XXXXX}}{{^issue.customfield_XXXXX}}false{{/issue.customfield_XXXXX}}
  }
}
```

**How the checkbox smart values work:**
- `{{#issue.customfield_10060}}true{{/issue.customfield_10060}}` → if checkbox is checked → outputs `true`
- `{{^issue.customfield_10060}}false{{/issue.customfield_10060}}` → if checkbox is NOT checked → outputs `false`
- Together they produce either `true` or `false` in the JSON

**If your Jira uses simple `{{issue.customfield_XXXXX}}` for checkboxes** (returns `true`/`false` directly), the body is simpler:

```json
{
  "event": "jira_workstation_request",
  "eventType": "issue_created",
  "sourceSystem": "jira",
  "ticket_id": "{{issue.key}}",
  "issueKey": "{{issue.key}}",
  "projectKey": "{{issue.project.key}}",
  "status": "{{issue.status.name}}",
  "summary": "{{issue.summary}}",
  "created": "{{issue.created}}",
  "updated": "{{issue.updated}}",
  "reporter_email": "{{issue.reporter.emailAddress}}",
  "reporter_display_name": "{{issue.reporter.displayName}}",
  "first_name": "{{issue.customfield_XXXXX}}",
  "group_name": "{{issue.customfield_XXXXX}}",
  "approvers": "{{issue.customfield_XXXXX}}",
  "software": {
    "chrome": {{issue.customfield_XXXXX}},
    "git": {{issue.customfield_XXXXX}},
    "python": {{issue.customfield_XXXXX}},
    "jupyterlab": {{issue.customfield_XXXXX}},
    "conda": {{issue.customfield_XXXXX}},
    "anaconda": {{issue.customfield_XXXXX}},
    "rstudio": {{issue.customfield_XXXXX}},
    "rstudio_pro": {{issue.customfield_XXXXX}},
    "pycharm_community": {{issue.customfield_XXXXX}},
    "visual_studio_community": {{issue.customfield_XXXXX}},
    "powershell_core": {{issue.customfield_XXXXX}},
    "positron": {{issue.customfield_XXXXX}},
    "paraview": {{issue.customfield_XXXXX}},
    "echoview": {{issue.customfield_XXXXX}},
    "echosms": {{issue.customfield_XXXXX}},
    "echostack": {{issue.customfield_XXXXX}},
    "matlab": {{issue.customfield_XXXXX}},
    "gpu_drivers": {{issue.customfield_XXXXX}},
    "oracle_client": {{issue.customfield_XXXXX}},
    "aalibrary": {{issue.customfield_XXXXX}},
    "gcp_utilities": {{issue.customfield_XXXXX}},
    "excel": {{issue.customfield_XXXXX}}
  }
}
```

### 4.5 Save the Action

```
Click "Save" on the web request action
```

### 4.6 Name and Enable the Rule

```
Rule name: "Trigger GCP Image Build on Workstation Request"
  → Click: Turn it on (toggle in top-right)
  → Click: Save rule
```

---

## Part 5: Test from Jira GUI

### 5.1 Create a test ticket

```
Your Project → + Create Issue
  → Issue Type: Workstation Request
  → Summary: "TEST - Chrome and Git only"
  → First Name: Your Name
  → Group Name: GARFO
  → Approver: Your Name
  → Check: ☑ Install Chrome
  → Check: ☑ Install Git
  → Leave all others unchecked
  → Click: Create
```

### 5.2 Check Automation logs

```
⚙️ Project Settings → Automation
  → Click on "Trigger GCP Image Build on Workstation Request"
  → Click "Audit log" tab
```

You should see:
```
✅ Rule completed successfully
   Trigger: Issue created (NOAA-XX)
   Action: Send web request → Status: 200
```

If you see:
```
❌ Rule failed
   Action: Send web request → Status: 401
```
→ The `X-Jira-Secret` header value doesn't match Secret Manager. Fix it in the Automation rule.

```
❌ Rule failed
   Action: Send web request → Status: 400
```
→ Check the response body in the audit log — it will tell you which field is missing.

### 5.3 Verify in GCP

```bash
# Check raw bucket
gsutil ls gs://nmfs-winde-jira-raw-dev/jira/raw/

# Check request bucket
gsutil ls gs://${PROJECT_ID}-image-builder-requests/requests/ | grep jira-NOAA

# Check BigQuery
bq query --use_legacy_sql=false \
  "SELECT issue_key, reporter_email, ingested_at
   FROM \`${PROJECT_ID}.jira_raw.issue_events\`
   ORDER BY ingested_at DESC LIMIT 3"

# Check Cloud Run job
gcloud run jobs executions list --job=windows-image-builder \
  --region=us-east4 --project=${PROJECT_ID} --limit=3
```

---

## Part 6: (Optional) Add Status Update Rule

When the build completes, you can automatically transition the Jira ticket. This requires a **second Automation rule** triggered by an incoming webhook from GCP.

> **Note:** This is a future enhancement. Currently the user gets an email notification via SendGrid. Jira ticket status update requires storing a Jira API token in GCP Secret Manager and adding callback code to the notify-email Cloud Function.

---

## Quick Reference: Jira Automation Smart Values

| Smart Value | What It Returns | Example |
|------------|----------------|---------|
| `{{issue.key}}` | Issue key | `NOAA-4` |
| `{{issue.project.key}}` | Project key | `NOAA` |
| `{{issue.status.name}}` | Current status | `To Do` |
| `{{issue.summary}}` | Summary text | `Need dev workstation` |
| `{{issue.created}}` | Created timestamp | `2026-06-29T12:00:00.000+0000` |
| `{{issue.updated}}` | Updated timestamp | `2026-06-29T12:00:00.000+0000` |
| `{{issue.reporter.emailAddress}}` | Reporter email | `steven@gmail.com` |
| `{{issue.reporter.displayName}}` | Reporter full name | `Steven Smith` |
| `{{issue.customfield_XXXXX}}` | Custom field value | `true` / `false` / `GARFO` |

---

## Troubleshooting Jira Side

| Problem | Cause | Fix |
|---------|-------|-----|
| Automation rule not firing | Rule disabled or condition wrong | Check rule is ON, condition matches issue type |
| Web request returns 401 | Secret mismatch | Update `X-Jira-Secret` header in Automation rule |
| Web request returns 400 | Missing fields in body template | Check field IDs are correct, test payload in audit log |
| Web request returns 403 | Cloud Run IAM issue | Verify `allUsers` has `run.invoker` on jira-ingest-api |
| Checkbox sends `"Checked"` not `true` | Jira field type mismatch | Use the `{{#}}true{{/}}{{^}}false{{/}}` syntax |
| Custom field returns empty | Wrong field ID | Double-check ID via REST API: `GET /rest/api/3/field` |
| Smart value returns `null` | Field not on the screen | Add field to issue type screen layout |
| Rule fires for all issues | Missing condition | Add "Issue fields condition: Type = Workstation Request" |
