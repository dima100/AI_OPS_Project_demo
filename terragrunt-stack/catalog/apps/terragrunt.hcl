include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env      = local.env_vars.locals.environment
  project  = local.env_vars.locals.project_id
  region   = local.env_vars.locals.region
  zone     = local.env_vars.locals.zone
  raw_ca_cert = local.env_vars.locals.raw_ca_cert
}



terraform {
  source = "${get_repo_root()}/terraform/modules/k8s_workloads"
}


// dependency "k8sgpt_operator" {
//   config_path = "${get_repo_root()}/terraform/modules/k8s_workloads"
//   # Ensure the operator (and CRD) is applied before planning this module
//   skip_outputs = true
// }

generate "k8s_provider" {
  path      = "k8s_provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "google_client_config" "default" {}

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "kubernetes" {
  host                   = "https://$${var.gke_endpoint}"
  cluster_ca_certificate = base64decode("$${var.gke_ca_certificate}")
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://$${var.gke_endpoint}"
    cluster_ca_certificate = base64decode("$${var.gke_ca_certificate}")
    token                  = data.google_client_config.default.access_token
  }
}
EOF
}

