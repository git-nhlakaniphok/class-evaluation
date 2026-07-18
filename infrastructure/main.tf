locals {
  base_apis = [
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]

  required_apis = local.base_apis

  deploy_project_roles = toset([
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
    "roles/secretmanager.admin",
  ])

  # Parse database connection string: postgresql://user:password@host:port/database
  # Named groups: user, password, host, port, database
  db_parts = regex("^postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^/:]+)(?::(?P<port>[0-9]+))?/(?P<database>[^?]+)", var.db_connection_string)

  db_user     = local.db_parts["user"]
  db_password = local.db_parts["password"]
  db_host     = local.db_parts["host"]
  db_port     = lookup(local.db_parts, "port", null) != "" && lookup(local.db_parts, "port", null) != null ? local.db_parts["port"] : "5432"
  db_database = local.db_parts["database"]
}

data "google_project" "project" {}

# Enable required GCP APIs
resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Runtime service account for n8n container
resource "google_service_account" "n8n_run" {
  project      = var.project_id
  account_id   = "${var.service_name}-run"
  display_name = "Runtime SA for ${var.service_name}"
}

# --- Secret Manager Setup for Database Password ---
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.service_name}-db-password"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = local.db_password
}

# --- Secret Manager Setup for n8n Encryption Key ---
# A stable key must be provided so credentials saved in n8n database are decryptable across restarts.
resource "random_id" "n8n_encryption_key" {
  byte_length = 24
}

resource "google_secret_manager_secret" "n8n_encryption_key" {
  project   = var.project_id
  secret_id = "${var.service_name}-encryption-key"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "n8n_encryption_key" {
  secret      = google_secret_manager_secret.n8n_encryption_key.id
  secret_data = random_id.n8n_encryption_key.hex
}

# --- IAM permissions for Runtime SA to read secrets ---
resource "google_secret_manager_secret_iam_member" "n8n_run_db_password_secret" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_run.email}"
}

resource "google_secret_manager_secret_iam_member" "n8n_run_enc_key_secret" {
  secret_id = google_secret_manager_secret.n8n_encryption_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_run.email}"
}

# --- Cloud Run v2 service for n8n ---
resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  name                = var.service_name
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.n8n_run.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.n8n_image

      ports {
        container_port = 5678 # n8n default port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Database Configuration (Postgresdb)
      env {
        name  = "DB_TYPE"
        value = "postgresdb"
      }

      env {
        name  = "DB_POSTGRESDB_HOST"
        value = local.db_host
      }

      env {
        name  = "DB_POSTGRESDB_PORT"
        value = local.db_port
      }

      env {
        name  = "DB_POSTGRESDB_USER"
        value = local.db_user
      }

      env {
        name  = "DB_POSTGRESDB_DATABASE"
        value = local.db_database
      }

      env {
        name = "DB_POSTGRESDB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      # Encryption Key
      env {
        name = "N8N_ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.n8n_encryption_key.secret_id
            version = "latest"
          }
        }
      }

      # Host and Webhook settings for Domain Exposure
      env {
        name  = "N8N_HOST"
        value = var.domain_name
      }

      env {
        name  = "N8N_PORT"
        value = "5678"
      }

      env {
        name  = "N8N_PROTOCOL"
        value = "https"
      }

      env {
        name  = "N8N_WEBHOOK_URL"
        value = "https://${var.domain_name}/"
      }

      env {
        name  = "WEBHOOK_URL"
        value = "https://${var.domain_name}/"
      }

      # Production Optimizations
      env {
        name  = "N8N_DEFAULT_BINARY_DATA_MODE"
        value = "database" # Keep binary payloads in Neon DB instead of ephemeral /tmp filesystem
      }

      env {
        name  = "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS"
        value = "false"
      }

      env {
        name  = "DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED"
        value = "false" # Allows connecting to Neon DB SSL endpoints
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.n8n_encryption_key,
    google_secret_manager_secret_iam_member.n8n_run_db_password_secret,
    google_secret_manager_secret_iam_member.n8n_run_enc_key_secret
  ]
}

# Public invoker permission so external users and the orchestration API can reach n8n
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Workload Identity Federation (WIF) setup for GitHub Actions deploy ---
resource "google_project_iam_member" "deploy_roles" {
  for_each = var.deploy_service_account != "" ? local.deploy_project_roles : toset([])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${var.deploy_service_account}"
}

resource "google_service_account_iam_member" "github_wif_workload_identity" {
  count              = var.deploy_service_account != "" ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.deploy_service_account}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/lunge-github-pool/attribute.repository/${var.github_repository}"
}

# --- Optional Cloud Run Domain Mapping ---
resource "google_cloud_run_domain_mapping" "this" {
  count    = var.create_domain_mapping ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = var.domain_name

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.this.name
  }
}

# --- Grant Storage Object Viewer to the n8n Cloud Run Service Account ---
resource "google_project_iam_member" "n8n_run_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.n8n_run.email}"
}
