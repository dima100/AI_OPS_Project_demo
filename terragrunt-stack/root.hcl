locals {
  env_vars   = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_id = local.env_vars.locals.project_id
  region     = local.env_vars.locals.region
  raw_ca_cert = local.env_vars.locals.raw_ca_cert
}

# Auto-generate provider.tf for every unit
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "google" {
  project = "${local.project_id}"
  region  = "${local.region}"
}
EOF
}

# Automatically enable required GCP APIs before provisioning
generate "enable_apis" {
  path      = "enable_apis.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
resource "google_project_service" "compute_api" {
  project            = "${local.project_id}"
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container_api" {
  project            = "${local.project_id}"
  service            = "container.googleapis.com"
  disable_on_destroy = false
}
EOF
}

# Store each unit's state in Google Cloud Storage
remote_state {
  backend = "gcs"
  config = {
    bucket   = "${local.project_id}-terragrunt-tfstate"
    prefix   = "${path_relative_to_include()}"
    location = local.region
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}