# Rendered by argo_cd.tf via templatefile() — do not edit directly, edit
# argo_cd.tf / variables.tf instead.
applications:
  - name: ${app_name}
    project: default
    source:
      repoURL: ${git_repo_url}
      path: ${app_chart_path}
      targetRevision: ${git_branch}
      helm:
        valueFiles:
          - values.yaml
        # charts/django-app/values.yaml intentionally ships placeholders for
        # these (image.repository / both secrets) -- same values a human
        # would pass via `helm install --set ...` per the README, just
        # supplied here so Argo CD's automated sync doesn't deploy the
        # literal placeholder strings.
        parameters:
          - name: image.repository
            value: "${app_image_repository}"
          - name: secrets.POSTGRES_PASSWORD
            value: "${app_postgres_password}"
            forceString: true
          - name: secrets.DJANGO_SECRET_KEY
            value: "${app_django_secret_key}"
            forceString: true
    destination:
      server: https://kubernetes.default.svc
      namespace: ${app_namespace}
    syncPolicy:
      automated:
        prune: true
        selfHeal: true

# Repository credentials, rendered into a Kubernetes Secret
# (templates/repository.yaml) with the argocd.argoproj.io/secret-type:
# repository label — Argo CD's standard declarative way to register a
# private repo, picked up automatically without touching the UI.
repositories:
  - name: django-app-repo
    url: ${git_repo_url}
    username: ${github_username}
    password: ${github_pat}
