terraform {
  required_version = ">= 1.5.0"
  kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0" # Use the version matching your setup
   }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.26"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Получаем временный OAuth2 токен для доступа к API кластера GKE
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}