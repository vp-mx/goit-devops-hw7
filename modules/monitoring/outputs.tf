output "namespace" {
  description = "Namespace the monitoring stack is installed into"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name of the kube-prometheus-stack install"
  value       = helm_release.kube_prometheus_stack.name
}

output "grafana_admin_password" {
  description = "Grafana admin password (username: admin). Sensitive -- read it with `terraform output -raw grafana_admin_password`."
  value       = local.effective_grafana_admin_password
  sensitive   = true
}

output "grafana_port_forward_command" {
  description = "Command to reach Grafana locally (service is ClusterIP on purpose -- see values.yaml)"
  value       = "kubectl port-forward -n ${var.namespace} svc/grafana 3000:80"
}

output "prometheus_port_forward_command" {
  description = "Command to reach the Prometheus UI locally"
  value       = "kubectl port-forward -n ${var.namespace} svc/kube-prometheus-stack-prometheus 9090:9090"
}
