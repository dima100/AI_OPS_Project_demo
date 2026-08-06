variable "monitoring_namespace" {
  type        = string
  default     = "monitoring"
  description = "K8s namespace для стекa Prometheus + Grafana"
}

variable "gke_endpoint" {
  type    = string
  default = "127.0.0.1"
}

variable "gke_ca_certificate" {
  type    = string
  default = ""
}

variable "ai_token" {
  type    = string
  default = "xxx"
}