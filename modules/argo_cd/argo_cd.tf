# Argo CD: the GitOps controller. helm_release.argo_cd installs the
# platform itself (server, repo-server, application-controller, redis).
# helm_release.argo_apps installs our own tiny local chart (./charts) that
# declares the Application CRD for django-app and the repository-credential
# Secret Argo CD needs to read this (private) Git repo.
resource "helm_release" "argo_cd" {
  name             = var.name
  namespace        = var.namespace
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  create_namespace = true

  values = [
    file("${path.module}/values.yaml")
  ]
}

resource "helm_release" "argo_apps" {
  name             = "${var.name}-apps"
  chart            = "${path.module}/charts"
  namespace        = var.namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/charts/values.yaml.tpl", {
      app_name        = var.app_name
      app_chart_path  = var.app_chart_path
      app_namespace   = var.app_namespace
      git_repo_url    = var.git_repo_url
      git_branch      = var.git_branch
      github_username = var.github_username
      github_pat      = var.github_pat
    })
  ]

  depends_on = [helm_release.argo_cd]
}
