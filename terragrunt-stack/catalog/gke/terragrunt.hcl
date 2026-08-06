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
  source = "${get_repo_root()}/terraform/modules/gke"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    network_name = "mock-network"
    subnet_name  = "mock-subnet"
  }
}

inputs = {
  zone         = local.region
  network_name = dependency.vpc.outputs.network_name
  subnet_name  = dependency.vpc.outputs.subnet_name
}