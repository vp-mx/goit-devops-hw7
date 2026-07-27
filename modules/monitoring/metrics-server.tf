# metrics-server -- feeds `kubectl top` and the HorizontalPodAutoscaler in
# charts/django-app/templates/hpa.yaml. Without it, `kubectl get hpa` shows
# TARGETS as <unknown> forever instead of a real CPU percentage. Grouped
# with the rest of monitoring since the final project grades "моніторинг
# та автомасштабування" as one criterion.
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = "kube-system"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  create_namespace = false

  set {
    name  = "resources.requests.cpu"
    value = "20m"
  }
  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  # EKS worker node kubelet serving certs aren't always signed for a name
  # metrics-server's default verification recognizes -- without this it
  # sits at "cannot validate certificate" and `kubectl top` / the HPA never
  # get real numbers.
  set_list {
    name  = "args"
    value = ["--kubelet-insecure-tls"]
  }
}
