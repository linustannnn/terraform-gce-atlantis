terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }

  backend "gcs" {
    bucket = "terraform-state-bucket-atlantis-test-439520"
  }
}

locals {
  project_id   = "atlantis-test-439520"
  region       = "us-east4"
  zone         = "us-east4-c"
  domain       = null # Since no domain, set this to null
  managed_zone = "us-east4-c"
}

# Service Account for Atlantis
resource "google_service_account" "atlantis" {
  account_id   = "atlantis-sa"
  display_name = "Service Account for Atlantis"
  project      = local.project_id
}

resource "google_project_iam_member" "atlantis_log_writer" {
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.atlantis.email}"
  project = local.project_id
}

resource "google_project_iam_member" "atlantis_metric_writer" {
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.atlantis.email}"
  project = local.project_id
}

# Compute Engine API
resource "google_project_service" "compute" {
  service                    = "compute.googleapis.com"
  project                    = local.project_id
  disable_dependent_services = false
  disable_on_destroy         = true
}

# Network configuration
resource "google_compute_network" "default" {
  name                    = "example-network"
  auto_create_subnetworks = false
  project                 = local.project_id
}

resource "google_compute_subnetwork" "default" {
  name                     = "example-subnetwork"
  ip_cidr_range            = "10.2.0.0/16"
  region                   = local.region
  network                  = google_compute_network.default.id
  project                  = local.project_id
  private_ip_google_access = true
  #   private_ipv6_google_access = "BIDIRECTIONAL"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create a router, which we associate the Cloud NAT too
resource "google_compute_router" "default" {
  name    = "example-router"
  region  = google_compute_subnetwork.default.region
  network = google_compute_network.default.name

  bgp {
    asn = 64514
  }
  project = local.project_id
}

# Create a NAT for outbound internet traffic
resource "google_compute_router_nat" "default" {
  name                               = "example-router-nat"
  router                             = google_compute_router.default.name
  region                             = google_compute_router.default.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = local.project_id
}

module "atlantis" {
  source     = "./atlantis"
  name       = "atlantis"
  network    = google_compute_network.default.name
  subnetwork = google_compute_subnetwork.default.name
  region     = local.region
  zone       = local.zone
  service_account = {
    email  = google_service_account.atlantis.email
    scopes = ["cloud-platform"]
  }
  # Note: environment variables are shown in the Google Cloud UI
  # See the `examples/secure-env-vars` if you want to protect sensitive information
  env_vars = {
    ATLANTIS_GH_USER           = var.github_user
    ATLANTIS_GH_TOKEN          = var.github_token
    ATLANTIS_GH_WEBHOOK_SECRET = var.github_webhook_secret
    ATLANTIS_REPO_ALLOWLIST    = var.github_repo_allow_list
    ATLANTIS_ATLANTIS_URL      = "http://34.107.167.149" # Use IP here
    ATLANTIS_REPO_CONFIG_JSON  = jsonencode(yamldecode(file("${path.module}/server-atlantis.yaml")))
  }
  domain  = null # No domain since we use a public IP
  project = local.project_id
}

# Disable DNS and SSL as we won't be using a domain or HTTPS
# resource "google_compute_ssl_policy" "default" {
#   name            = "example-ssl-policy"
#   profile         = "RESTRICTED"
#   min_tls_version = "TLS_1_2"
#   project         = local.project_id
# }

#---------------------------------------------------------------#

resource "google_storage_bucket" "terraform_state" {
  name                        = "terraform-state-bucket-${local.project_id}"
  location                    = "US"
  storage_class               = "STANDARD"
  project                     = local.project_id
  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}
