module "vpc" {
  source = "./modules/vpc"
  region = var.region
}

module "gke" {
  source       = "./modules/gke"
  zone         = var.zone
  network_name = module.vpc.network_name
  subnet_name  = module.vpc.subnet_name
}

module "k8s_workloads" {
  source     = "./modules/k8s_workloads"
  depends_on = [module.gke]
}