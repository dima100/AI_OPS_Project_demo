locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  token_vars = read_terragrunt_config(find_in_parent_folders("tokens.yaml"))
  project_id =  local.env_vars.locals.project_id
  env      = local.env_vars.locals.environment
  project  = local.env_vars.locals.project_id
  region   = local.env_vars.locals.region
  zone     = local.env_vars.locals.zone
  raw_ca_cert = local.env_vars.locals.raw_ca_cert
  ai_token = local.token_vars.locals.ai_token
  github_token = local.token_vars.locals.github_token
}



unit "vpc" {
  source = "${get_repo_root()}/terragrunt-stack/catalog/vpc"
  path   = "vpc"

  values = {
    region = local.region
  }
}

unit "gke" {
  source = "${get_repo_root()}/terragrunt-stack/catalog/gke"
  path   = "gke"

  values = {
    zone = local.zone
  }

  autoinclude {
    dependency "vpc" {
      config_path = unit.vpc.path
      mock_outputs = {
        network_name = "mock-network"
        subnet_name  = "mock-subnet"
      }
    }
    inputs = {
      network_name = dependency.vpc.outputs.network_name
      subnet_name  = dependency.vpc.outputs.subnet_name
      project_id = local.project_id
      region = local.region
    }

  }
}


unit "apps" {
  source = "${get_repo_root()}/terragrunt-stack/catalog/apps"
  path   = "apps"

  autoinclude {
    dependency "gke" {
      config_path = unit.gke.path
      mock_outputs = {
        endpoint       = "127.0.0.1"
        ca_certificate = base64encode(local.raw_ca_cert)
      }
      mock_outputs_allowed_terraform_commands = ["validate", "plan","destroy"]
      mock_outputs_merge_strategy_with_state  = "shallow"
    }
    inputs = {
      gke_endpoint       = dependency.gke.outputs.endpoint
      gke_ca_certificate = dependency.gke.outputs.ca_certificate
      ai_token = local.ai_token
      github_token = local.github_token
    }
  }
}
