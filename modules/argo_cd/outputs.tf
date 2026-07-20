output "argo_cd_server_service" {
  description = "In-cluster DNS name of the Argo CD server"
  value       = "argocd-server.${var.namespace}.svc.cluster.local"
}

output "admin_password_command" {
  description = "Run this to fetch the initial admin password"
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_url_command" {
  description = "Command to fetch the external LoadBalancer hostname for the Argo CD UI"
  value       = "kubectl get svc argocd-server -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "application_name" {
  description = "Name of the Argo CD Application that deploys charts/django-app"
  value       = var.app_name
}
