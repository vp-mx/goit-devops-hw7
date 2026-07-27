variable "namespace" {
  description = "Kubernetes namespace the monitoring stack is installed into"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "prometheus-community/kube-prometheus-stack chart version"
  type        = string
  default     = "87.19.2"
}

variable "metrics_server_chart_version" {
  description = "metrics-server/metrics-server chart version"
  type        = string
  default     = "3.13.1"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Leave null to have the module generate and store a random one in Terraform state (read it back via the sensitive grafana_admin_password output)."
  type        = string
  default     = null
  sensitive   = true
}
