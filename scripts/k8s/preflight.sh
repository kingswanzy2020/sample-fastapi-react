#!/bin/bash
# Check the local cluster is ready for scripts/k8s/deploy-local.sh.
# Read-only apart from one short-lived probe pod, which it deletes.
# See docs/ARCHITECTURE.md §16.5.

set -euo pipefail
# shellcheck source=scripts/k8s/lib.sh
source "$(dirname "$0")/lib.sh"

require_local_context
echo "✓ context: $CONTEXT ($CLUSTER_KIND)"

# --- nodes -----------------------------------------------------------------
workers=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l)
kubectl get nodes
if [ "$workers" -lt 2 ]; then
  echo "! only $workers schedulable worker node(s). Anti-affinity, PDBs and the"
  echo "  node-drain drill (§18.4) need two. Docker Desktop: Settings -> Kubernetes"
  echo "  -> kind, 3 nodes. Standalone kind: deploy/kind/kind-config.yaml."
else
  echo "✓ $workers worker nodes"
fi

# --- add-ons ---------------------------------------------------------------
kubectl get ingressclass traefik >/dev/null 2>&1 \
  && echo "✓ traefik ingress class" \
  || echo "! no traefik ingress class -- run scripts/k8s/addons.sh"
kubectl top nodes >/dev/null 2>&1 \
  && echo "✓ metrics-server answering" \
  || echo "! kubectl top fails -- metrics-server missing or still starting (scripts/k8s/addons.sh)"

# --- can the nodes see locally built images? -------------------------------
# kind nodes run their own containerd, separate from the Docker Engine's image
# store. Standalone kind needs `kind load`; for Docker Desktop, test it.
if [ "$CLUSTER_KIND" = kind ]; then
  echo "✓ standalone kind: deploy-local.sh loads images with 'kind load docker-image'"
  exit 0
fi

probe_image=fastapi-react/preflight-probe:local
printf 'FROM busybox:1.37\nCMD ["true"]\n' | docker build -q -t "$probe_image" - >/dev/null
kubectl run k8s-preflight-probe --image="$probe_image" --image-pull-policy=Never \
  --restart=Never >/dev/null
for _ in $(seq 1 30); do
  reason=$(kubectl get pod k8s-preflight-probe \
    -o jsonpath='{.status.phase}{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  case "$reason" in
    Succeeded*|Running*) break ;;
    *ErrImageNeverPull*) break ;;
  esac
  sleep 1
done
kubectl delete pod k8s-preflight-probe --wait=false >/dev/null 2>&1 || true

case "$reason" in
  Succeeded*|Running*)
    echo "✓ nodes see images built with 'docker build' -- nothing to load" ;;
  *ErrImageNeverPull*)
    echo "✗ nodes do NOT see locally built images."
    echo "  Use a local registry the nodes can reach and set image.registry to it"
    echo "  (docs/ARCHITECTURE.md §16.5), or use standalone kind."
    exit 1 ;;
  *)
    echo "? probe did not finish (last state: '${reason:-unknown}'); inspect with"
    echo "  kubectl describe pod k8s-preflight-probe"
    exit 1 ;;
esac
