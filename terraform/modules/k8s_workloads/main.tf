# 1. Prometheus + Grafana Stack via Helm
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [<<EOT
grafana:
  adminPassword: "admin-super-secret"
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
EOT
  ]
}


# 1. Official Helm Chart deployment for the K8sGPT operator
resource "helm_release" "k8sgpt_operator" {
  depends_on = [helm_release.k8sgpt_operator]
  name             = "k8sgpt-operator"
  repository       = "https://charts.k8sgpt.ai"
  chart            = "k8sgpt-operator"
  namespace        = "k8sgpt-operator-system"
  create_namespace = true

  values = [
    yamlencode({
      serviceMonitor = {
        enabled = false
      }
    })
  ]
}


resource "helm_release" "nats" {
  name       = "nats-service"
  repository = "https://nats-io.github.io/k8s/helm/charts/"
  chart      = "nats"
  namespace  = "default"

  # We force the service name to exactly match what your Python scripts expect
  set {
    name  = "fullnameOverride"
    value = "nats-service"
  }

  # Keep it lightweight for your spot-node practice cluster
  set {
    name  = "cluster.enabled"
    value = "false"
  }


}


# 2. Deploy vLLM via the official production stack chart
# resource "helm_release" "vllm" {
#   name             = "vllm-server"
#   repository       = "https://vllm-project.github.io/production-stack"
#   chart            = "vllm-stack"
#   namespace        = "ai-serving"
#   create_namespace = true
#
#   timeout = 1200
#
#   values = [
#     yamlencode({
#       # Note: vllm-stack splits config into components (e.g. engine, router)
#       engine = {
#         pvcStorage    = "20Gi"
#         pvcAccessMode = ["ReadWriteOnce"]
#         storageClass  = "standard" # Set your Kubernetes cluster's storage class (e.g. gp2, local-path)
#
#         resources = {
#           requests = {
#             cpu    = "4"
#             memory = "16Gi"
#           }
#           limits = {
#             cpu    = "8"
#             memory = "32Gi"
#           }
#         }
#         extraArgs = [
#           "--model", "Qwen/Qwen2.5-1.5B-Instruct",
#           "--device", "cpu", # Forces CPU inference for free accounts
#           "--port", "8000"
#         ]
#       }
#     })
#   ]
# }

# 3. Create a dummy secret required by the K8sGPT OpenAI structural validator
resource "kubernetes_secret" "k8sgpt_api_key" {
  depends_on = [helm_release.k8sgpt_operator] # Ensures namespace exists

  metadata {
    name      = "k8sgpt-api-key"
    namespace = "k8sgpt-operator-system"
  }

  data = {
    "api-key" = var.ai_token
  }
}


resource "time_sleep" "wait_for_k8sgpt_crds" {
  depends_on = [
    helm_release.k8sgpt_operator
  ]

  # Gives the Kubernetes API server 30 seconds to register the CRD
  create_duration = "30s"
}

# 4. Deploy the K8sGPT analyzer binding configuration
resource "kubectl_manifest" "k8sgpt_config" {
  depends_on = [
    helm_release.k8sgpt_operator,
    kubernetes_secret.k8sgpt_api_key
  ]

  yaml_body = <<-YAML
    apiVersion: core.k8sgpt.ai/v1alpha1
    kind: K8sGPT
    metadata:
      name: k8sgpt-openai
      namespace: k8sgpt-operator-system
    spec:
      version: "v0.3.48"
      ai:
        enabled: true
        backend: openai
        model: gpt-4o-mini
        secret:
          name: k8sgpt-api-key
          key: api-key
      anonymize: false
  YAML
}

# -------------------------------------------------------------------------
# 2. Deploy mysql DB & Service
# -------------------------------------------------------------------------



resource "kubernetes_deployment_v1" "mysql_db" {
  depends_on = [helm_release.kube_prometheus_stack]

  metadata {
    name      = "mysql-db"
    namespace = "default"
    labels = {
      app = "mysql-db"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mysql-db"
      }
    }
    template {
      metadata {
        labels = {
          app = "mysql-db"
        }
      }
      spec {
        container {
          name  = "mysql"
          image = "mysql:8.0"

          env {
            name  = "MYSQL_DATABASE"
            value = "wordpress"
          }
          env {
            name  = "MYSQL_USER"
            value = "wp_user"
          }
          env {
            name  = "MYSQL_PASSWORD"
            value = "wp_password123"
          }
          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = "root_password123"
          }

          port {
            container_port = 3306
            name           = "mysql"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "mysql_db_svc" {
  depends_on = [kubernetes_deployment_v1.mysql_db]

  metadata {
    name      = "mysql-db"
    namespace = "default"
  }

  spec {
    selector = {
      app = "mysql-db"
    }
    port {
      name        = "mysql"
      port        = 3306
      target_port = 3306
    }
  }
}


# -------------------------------------------------------------------------
# 4. Deploy Database Exporter Stack
# -------------------------------------------------------------------------
resource "kubectl_manifest" "mysql_exporter_deployment" {
  yaml_body  = file("${path.module}/templates/mysql-exporter-deployment.yaml")
  depends_on = [
    kubernetes_service_v1.mysql_db_svc,
    kubectl_manifest.mysql_otel_credentials
  ]
}

resource "kubectl_manifest" "mysql_exporter_service" {
  yaml_body  = file("${path.module}/templates/mysql-exporter-service.yaml")
  depends_on = [kubectl_manifest.mysql_exporter_deployment]
}

# -------------------------------------------------------------------------
# 5. Grafana Dashboard ConfigMap
# -------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "grafana_dashboard" {
  depends_on = [helm_release.kube_prometheus_stack]

  metadata {
    name      = "grafana-dashboard-custom"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "custom-dashboard.json" = <<EOF
{
  "title": "MySQL & App Overview",
  "panels": [
    {
      "type": "stat",
      "title": "MySQL Up Status",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "targets": [
        { "expr": "mysql_up", "legendFormat": "MySQL Status" }
      ]
    }
  ]
}
EOF
  }
}

# -------------------------------------------------------------------------
# 6. ServiceMonitor (Custom Resource Definition)
# -------------------------------------------------------------------------
resource "kubectl_manifest" "mysql_exporter_servicemonitor" {
  depends_on = [
    helm_release.kube_prometheus_stack,
    kubectl_manifest.mysql_exporter_service
  ]
  yaml_body = file("${path.module}/templates/mysql-exporter-servicemonitor.yaml")
}

# Add to modules/k8s_workloads/main.tf

resource "kubectl_manifest" "otel_collector_config" {
  yaml_body = file("${path.module}/templates/otel-collector-config.yaml")
}

resource "kubectl_manifest" "otel_collector_deployment" {
  yaml_body  = file("${path.module}/templates/otel-collector-deployment.yaml")
  depends_on = [kubectl_manifest.otel_collector_config]
}

resource "kubectl_manifest" "otel_collector_svc" {
  yaml_body  = file("${path.module}/templates/otel-collector-svc.yaml")
  depends_on = [kubectl_manifest.otel_collector_deployment]
}

resource "kubectl_manifest" "otel_collector_servicemonitor" {
  yaml_body  = file("${path.module}/templates/otel-collector-servicemonitor.yaml")
  depends_on = [kubectl_manifest.otel_collector_svc]
}

resource "kubectl_manifest" "jaeger_deployment" {
  yaml_body = file("${path.module}/templates/jaeger-deployment.yaml")
}

resource "kubectl_manifest" "jaeger_collector_svc" {
  yaml_body  = file("${path.module}/templates/jaeger-collector-svc.yaml")
  depends_on = [kubectl_manifest.jaeger_deployment]
}

resource "kubectl_manifest" "jaeger_ui_svc" {
  yaml_body  = file("${path.module}/templates/jaeger-ui-svc.yaml")
  depends_on = [kubectl_manifest.jaeger_deployment]
}

# MySQL exporter credentials
resource "kubectl_manifest" "mysql_otel_credentials" {
  yaml_body  = file("${path.module}/templates/mysql-otel-credentials-secret.yaml")
  depends_on = [helm_release.kube_prometheus_stack]
}

# WordPress OTel ConfigMap
# resource "kubectl_manifest" "wordpress_otel_config" {
#   yaml_body = file("${path.module}/templates/wordpress-otel-config.yaml")
# }

# WordPress with OTel instrumentation (replaces existing wordpress deployment)
# resource "kubectl_manifest" "wordpress_instrumented" {
#   yaml_body  = file("${path.module}/templates/wordpress-instrumented.yaml")
#   depends_on = [
#     kubernetes_service_v1.mysql_db_svc,
#     kubectl_manifest.otel_collector,
#     kubectl_manifest.wordpress_otel_config
#   ]
# }


resource "kubectl_manifest" "otel_demo_frontend" {
  yaml_body  = file("${path.module}/templates/otel-demo-frontend.yaml")
  depends_on = [kubectl_manifest.otel_collector_svc]
}

resource "kubectl_manifest" "otel_demo_frontend_svc" {
  yaml_body  = file("${path.module}/templates/otel-demo-frontend-svc.yaml")
  depends_on = [kubectl_manifest.otel_demo_frontend]
}


resource "kubectl_manifest" "dem_app_deployment" {
  yaml_body  = file("${path.module}/templates/demo-app-deployment.yaml")
  depends_on = [kubernetes_deployment_v1.mysql_db]
}