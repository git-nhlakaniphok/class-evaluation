# Self-Host n8n on Cloud Run with Neon DB

This repository provides the Terraform configuration and GitHub Actions workflows to self-host **n8n** in GCP Cloud Run, backed by a **Neon DB** PostgreSQL instance, exposed at `https://evaluations.lunge.co.za/`.

---

## Architecture Overview

1. **Cloud Run Service (`lunge-n8n`)**: Runs n8n inside a managed serverless container using the official `docker.io/n8nio/n8n:latest` image.
2. **Neon DB Connection**: Secured using GCP Secret Manager (`lunge-n8n-db-connection-string`). n8n connects via SSL.
3. **Encryption Key**: A unique encryption key (`lunge-n8n-encryption-key`) is auto-generated using Terraform's `random_id` and saved in Secret Manager, ensuring credentials stored in n8n remain decryptable across container scaling/restarts.
4. **Domain Mapping**: Maps the custom domain `evaluations.lunge.co.za` to the Cloud Run service instance.
5. **Workload Identity Federation**: Enables passwordless deployment from GitHub Actions using WIF.

---

## Prerequisites

Before running Terraform, complete these steps:

### 1. Verify the Domain in Google Cloud
Google Cloud requires you to prove ownership of the domain `lunge.co.za` before you can map a subdomain to Cloud Run.
- Navigate to the [Google Search Console](https://search.google.com/search-console).
- Add the property `lunge.co.za` and verify ownership.
- Alternatively, you can use the GCP Console [Domain Verification Page](https://console.cloud.google.com/apis/credentials/domainverification) using a verified account.
- If you wish to set up the domain mapping manually (e.g. via Load Balancer or Firebase Hosting), you can set `create_domain_mapping = false` in `terraform.tfvars`.

### 2. GCS Backend Bucket
The Terraform backend configuration is configured to store states in:
- Bucket: `lunge-tf-state-project-318d561e-57b2-4c9e-a90`
- Prefix: `lunge-n8n`

Ensure this bucket exists in the target GCP project before running `terraform init`.

---

## Local Deployment

1. Set up your Google Cloud authentication:
   ```bash
   gcloud auth application-default login
   ```
2. Navigate to the infrastructure folder:
   ```bash
   cd infrastructure
   ```
3. Initialize Terraform:
   ```bash
   terraform init
   ```
4. Plan changes:
   ```bash
   terraform plan
   ```
5. Apply the plan to deploy:
   ```bash
   terraform apply
   ```

---

## GitHub Actions Configuration

To enable CI/CD deployment from this repository, add the following secrets to your GitHub repository (**Settings > Secrets and variables > Actions**):

| Secret Name | Description | Example Value |
| :--- | :--- | :--- |
| `GCP_PROJECT_ID` | The ID of your Google Cloud project | `your-gcp-project-id` |
| `GCP_REGION` | GCP region for deployment | `europe-west1` |
| `DEPLOY_SERVICE_ACCOUNT` | The service account with deploy permissions | `your-deploy-sa@your-gcp-project-id.iam.gserviceaccount.com` |
| `WIF_PROVIDER` | Workload Identity Provider string | `projects/your-gcp-project-number/locations/global/workloadIdentityPools/...` |
| `N8N_DB_CONNECTION_STRING` | Neon DB Postgres Connection URL | `postgresql://neondb_owner:password@endpoint...` |

### Deploy Workflows

1. **Terraform CD (`terraform.yml`)**: Triggered on any push to `master`/`main` affecting files in `infrastructure/**`. It validates, plans, and applies Terraform modifications.
2. **Deploy n8n Update (`deploy.yml`)**: Triggered manually from the **Actions** tab. It permits updating n8n versions (e.g., to a specific tag like `1.50.1` or `latest`) on the fly.

---

## DNS Settings (Exposing the service)

Once the Terraform execution completes, if `create_domain_mapping = true` is set, GCP will provision an SSL certificate for `evaluations.lunge.co.za`. 
1. Run `terraform output` or inspect the Google Cloud Console for the Cloud Run Domain Mapping details.
2. It will provide the target records (usually a **CNAME** record pointing to `ghs.googlehosted.com.`, or multiple **A/AAAA** records).
3. Add these records in your DNS management panel (e.g. Cloudflare, Route53, or domain registrar) for `evaluations.lunge.co.za`.

---

## Direct Communication with Orchestration API

In the `lunge.orchestration` API, the class evaluations engine expects n8n webhooks.

### 1. n8n Workflow Webhooks
When you access the n8n dashboard at `https://evaluations.lunge.co.za/`:
- Create your **Setup Quiz** and **Mark Quiz** workflows.
- Add a **Webhook** node at the beginning of each workflow.
- Set the Webhook method to `POST`.
- Set the Webhook path (e.g. `/quiz/setup` and `/quiz/mark`). n8n will give you a webhook URL like `https://evaluations.lunge.co.za/webhook/some-uuid-path`.

### 2. Configure Authentication (X-Api-Key)
Since the orchestration API calls n8n with an API Key in the headers (`X-Api-Key` by default), configure your n8n webhook nodes:
- Select **Header Auth** under n8n Webhook authentication.
- Set the Header Name to `X-Api-Key`.
- Define a secret credentials object in n8n containing your API Key.

### 3. Configure Orchestration appsettings
In your orchestration deployment (`lunge.orchestration`), configure the `AIntelligent` settings in GCP Secret Manager or `appsettings.Production.json`:
```json
"AIntelligent": {
  "BaseUrl": "https://evaluations.lunge.co.za",
  "EvaluationSetupWebhookPath": "webhook/your-setup-webhook-uuid",
  "EvaluationMarkingWebhookPath": "webhook/your-marking-webhook-uuid",
  "ApiKeyHeaderName": "X-Api-Key",
  "TimeoutSeconds": 120
}
```
And make sure the mapped `ApiKey` matches the value configured in n8n's header verification!
# class-evaluation
# class-evaluation
