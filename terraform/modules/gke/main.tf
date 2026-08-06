# modules/gke/main.tf

# ---------------------------------------------------------
# 1. Artifact Registry for your AIOps Docker Images
# ---------------------------------------------------------
resource "google_artifact_registry_repository" "aiops_repo" {
  location      = var.region
  repository_id = "aiops-repo"
  description   = "Docker repository for AIOps Python agents and apps"
  format        = "DOCKER"
}

# ---------------------------------------------------------
# 2. Custom Service Account & Permissions
# ---------------------------------------------------------
# FIX 1: Create the service account referenced by the IAM binding
resource "google_service_account" "gke_node_sa" {
  account_id   = "aiops-gke-sa"
  display_name = "AIOps GKE Node Service Account"
}

locals {
  gke_node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader" # The one we added earlier
  ]
}

resource "google_project_iam_member" "gke_node_sa_roles" {
  for_each = toset(local.gke_node_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# Grant the GKE nodes permission to pull images from Artifact Registry
resource "google_project_iam_member" "gke_sa_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}


resource "google_container_cluster" "primary" {
  name                     = "gke-spot-cluster"
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = var.network_name
  subnetwork               = var.subnet_name
  deletion_protection      = false

  node_config {
    spot = true
    disk_size_gb = 30           # Drops temp disk usage to 10 GB
    disk_type    = "pd-standard" # Uses cheaper HDD quota
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-range"
    services_secondary_range_name = "services-range"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
    # Or restrict to specific IP:
    # cidr_blocks {
    #   cidr_block   = "YOUR_IP/32"
    #   display_name = "My IP"
    # }
  }
}


# Отдельный пул Spot-нод
resource "google_container_node_pool" "spot_nodes" {
  name       = "spot-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    spot         = true # <-- Экономия средств: Spot экземпляры
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-standard"
    service_account = google_service_account.gke_node_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

