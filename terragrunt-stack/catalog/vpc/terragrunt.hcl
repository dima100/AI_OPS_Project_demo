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
  source = "${get_repo_root()}/terraform/modules/vpc"
}

inputs = {
  region         = local.region
}


