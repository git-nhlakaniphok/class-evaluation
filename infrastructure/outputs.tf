output "service_url" {
  description = "Public URL of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.this.uri
}

output "service_name" {
  description = "Name of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.name
}

output "runtime_service_account" {
  description = "Email of the Cloud Run runtime service account."
  value       = google_service_account.n8n_run.email
}

output "domain_mapping_status" {
  description = "Domain Mapping Status resources if created."
  value       = length(google_cloud_run_domain_mapping.this) > 0 ? google_cloud_run_domain_mapping.this[0].status : null
}

output "load_balancer_ip" {
  description = "Static anycast IP of the load balancer. Create an A record for your domain pointing here."
  value       = var.enable_load_balancer ? google_compute_global_address.lb[0].address : null
}

output "custom_domain_url" {
  description = "Public URL users will access once DNS resolves and the cert is active."
  value       = var.enable_load_balancer ? "https://${var.domain_name}" : null
}
