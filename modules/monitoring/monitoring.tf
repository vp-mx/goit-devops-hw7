# Monitoring: Prometheus + Grafana via the kube-prometheus-stack umbrella
# chart (Prometheus Operator, Prometheus, Alertmanager, Grafana,
# kube-state-metrics, node-exporter -- Alertmanager is disabled, see
# values.yaml). Installed straight from Terraform, same pattern as
# modules/jenkins and modules/argo_cd.

resource "random_password" "grafana_admin" {
  count = var.grafana_admin_password == null ? 1 : 0

  length  = 20
  special = false
}

locals {
  effective_grafana_admin_password = coalesce(var.grafana_admin_password, try(random_password.grafana_admin[0].result, null))
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = var.namespace
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  create_namespace = true
  timeout          = 600 # first-time CRD install + several image pulls take longer than the 300s default

  values = [
    file("${path.module}/values.yaml")
  ]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = local.effective_grafana_admin_password
  }
}
