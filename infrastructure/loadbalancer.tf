# Global external HTTPS load balancer fronting the Cloud Run service.
# All resources are gated on var.enable_load_balancer.

# Serverless network endpoint group pointing at the Cloud Run service.
resource "google_compute_region_network_endpoint_group" "serverless" {
  count = var.enable_load_balancer ? 1 : 0

  project               = var.project_id
  name                  = "${var.service_name}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.this.name
  }

  depends_on = [google_project_service.apis]
}

# Reserved global anycast IP that the domain's A record will point to.
resource "google_compute_global_address" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  project = var.project_id
  name    = "${var.service_name}-ip"
}

# Google-managed TLS certificate for the custom domain.
resource "google_compute_managed_ssl_certificate" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  project = var.project_id
  name    = "${var.service_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  project               = var.project_id
  name                  = "${var.service_name}-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.serverless[0].id
  }
}

resource "google_compute_url_map" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  project         = var.project_id
  name            = "${var.service_name}-urlmap"
  default_service = google_compute_backend_service.lb[0].id
}

resource "google_compute_target_https_proxy" "lb" {
  count = var.enable_load_balancer ? 1 : 0

  project          = var.project_id
  name             = "${var.service_name}-https-proxy"
  url_map          = google_compute_url_map.lb[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.lb[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count = var.enable_load_balancer ? 1 : 0

  project               = var.project_id
  name                  = "${var.service_name}-https"
  target                = google_compute_target_https_proxy.lb[0].id
  ip_address            = google_compute_global_address.lb[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Redirect plain HTTP to HTTPS.
resource "google_compute_url_map" "redirect" {
  count = var.enable_load_balancer ? 1 : 0

  project = var.project_id
  name    = "${var.service_name}-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  count = var.enable_load_balancer ? 1 : 0

  project = var.project_id
  name    = "${var.service_name}-http-proxy"
  url_map = google_compute_url_map.redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = var.enable_load_balancer ? 1 : 0

  project               = var.project_id
  name                  = "${var.service_name}-http"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.lb[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
