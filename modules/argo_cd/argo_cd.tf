# Generated once and persisted in Terraform state, so they stay stable
# across applies (Argo CD would otherwise see a values diff and re-sync
# every run if these were regenerated each time). Equivalent to the
# `--set secrets.POSTGRES_PASSWORD=$(openssl rand -hex 16)` /
# `--set secrets.DJANGO_SECRET_KEY=...` a human runs manually per the README,
# just wired through Argo CD's Application instead.
resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "django_secret_key" {
  length  = 50
  special = true
  # Django's SECRET_KEY must not contain characters that break shell/YAML
  # quoting when passed through as a Helm --set-string style parameter.
  override_special = "!@#%^&*()-_=+"
}

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
  timeout          = 600 # a bit more headroom than the 300s default for first-time image pulls

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
      app_name              = var.app_name
      app_chart_path        = var.app_chart_path
      app_namespace         = var.app_namespace
      app_image_repository  = var.app_image_repository
      app_postgres_password = random_password.postgres_password.result
      app_django_secret_key = random_password.django_secret_key.result
      git_repo_url          = var.git_repo_url
      git_branch            = var.git_branch
      github_username       = var.github_username
      github_pat            = var.github_pat
    })
  ]

  depends_on = [helm_release.argo_cd]
}
