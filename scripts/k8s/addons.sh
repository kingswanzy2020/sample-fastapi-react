#!/bin/bash
# Install the cluster add-ons the chart depends on, into the LOCAL cluster:
#
#   traefik         ingress controller (ingressClassName: traefik)
#   metrics-server  CPU metrics for the HPA and `kubectl top`
#
# Idempotent: re-running upgrades in place. See docs/ARCHITECTURE.md §16.4.
# On EKS these come from terraform/environments/dev-k8s instead.

set -euo pipefail
# shellcheck source=scripts/k8s/lib.sh
source "$(dirname "$0")/lib.sh"

# Pinned: an unpinned chart is a different install every time someone runs this.
TRAEFIK_CHART_VERSION=41.6.0
METRICS_SERVER_CHART_VERSION=3.14.0

require_local_context
echo "context: $CONTEXT ($CLUSTER_KIND)"

helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update traefik metrics-server >/dev/null

traefik_args=()
if [ "$CLUSTER_KIND" = kind ]; then
  # Standalone kind: no LoadBalancer implementation. Bind host ports on the
  # control-plane node, which deploy/kind/kind-config.yaml maps to the host's
  # :80/:443 and labels ingress-ready=true.
  traefik_args+=(
    --set service.type=NodePort
    --set ports.web.hostPort=80
    --set ports.websecure.hostPort=443
    --set-string nodeSelector.ingress-ready=true
    --set 'tolerations[0].key=node-role.kubernetes.io/control-plane'
    --set 'tolerations[0].operator=Exists'
    --set 'tolerations[0].effect=NoSchedule'
  )
fi
# Docker Desktop: the chart's default Service type LoadBalancer is published
# on localhost by Docker Desktop itself.

helm upgrade --install traefik traefik/traefik \
  --version "$TRAEFIK_CHART_VERSION" \
  --namespace traefik --create-namespace \
  ${traefik_args[@]+"${traefik_args[@]}"} \
  --wait --timeout 5m

# kind's kubelets serve self-signed certificates; without this flag
# metrics-server cannot scrape them and the HPA shows <unknown>.
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version "$METRICS_SERVER_CHART_VERSION" \
  --namespace kube-system \
  --set 'args={--kubelet-insecure-tls}' \
  --wait --timeout 5m

kubectl get svc -n traefik traefik
cat <<EOF

Add-ons installed. Next:
  scripts/k8s/preflight.sh      # confirm the nodes can see locally built images
  scripts/k8s/deploy-local.sh   # build, load and deploy the app

If EXTERNAL-IP above stays <pending> on Docker Desktop, reach the ingress with:
  kubectl port-forward -n traefik svc/traefik 8080:80    # then http://localhost:8080/
Port 80 on the host must be free -- stop docker-compose.prod.yml if it is running.
EOF
