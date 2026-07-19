output "jenkins_release_name" {
  description = "Name of the Jenkins Helm release"
  value       = helm_release.jenkins.name
}

output "jenkins_namespace" {
  description = "Namespace Jenkins is deployed into"
  value       = var.namespace
}

output "jenkins_kaniko_role_arn" {
  description = "ARN of the IAM role jenkins-sa assumes to push to ECR"
  value       = aws_iam_role.jenkins_kaniko_role.arn
}

output "jenkins_url_command" {
  description = "Command to fetch the external LoadBalancer hostname for the Jenkins UI"
  value       = "kubectl get svc jenkins -n ${var.namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
