variable "project_id" {
  description = "The GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources (Cloud Run, Artifact Registry)."
  type        = string
  default     = "europe-west1"
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
  default     = "lunge-n8n"
}

variable "db_connection_string" {
  description = "Neon DB PostgreSQL connection string (postgresql://...)."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "External domain name to expose n8n (e.g. evaluations.lunge.co.za)."
  type        = string
  default     = "evaluations.lunge.co.za"
}

variable "create_domain_mapping" {
  description = "Whether to create the Cloud Run domain mapping. Requires domain verification beforehand."
  type        = bool
  default     = false
}

variable "deploy_service_account" {
  description = "The service account email used by GitHub Actions (DEPLOY_SERVICE_ACCOUNT)."
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "The GitHub repository path allowed to authenticate via Workload Identity Federation (e.g. Nkwakx/class-evaluations)."
  type        = string
  default     = "Nkwakx/class-evaluations"
}

variable "n8n_image" {
  description = "Container image for n8n. Cloud Run pulls this image."
  type        = string
  default     = "docker.io/n8nio/n8n:latest"
}

variable "cpu" {
  description = "CPU allocation per Cloud Run instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation per Cloud Run instance."
  type        = string
  default     = "2Gi"
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances (0 allows scale-to-zero)."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances."
  type        = number
  default     = 4
}

variable "labels" {
  description = "Labels applied to created resources."
  type        = map(string)
  default = {
    app        = "lunge-n8n"
    managed-by = "terraform"
  }
}
