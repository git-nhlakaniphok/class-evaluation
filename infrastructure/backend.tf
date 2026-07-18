terraform {
  backend "gcs" {
    bucket = "lunge-tf-state-project-318d561e-57b2-4c9e-a90"
    prefix = "lunge-n8n"
  }
}
