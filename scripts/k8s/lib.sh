#!/bin/bash
# shellcheck disable=SC2034  # everything here is used by the scripts that source this file
# Shared helpers for scripts/k8s/*. Sourced, not executed.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART="$REPO_ROOT/deploy/helm/fastapi-react"
LOCAL_SECRETS="$REPO_ROOT/deploy/kind/secrets.local.yaml"
NAMESPACE="${NAMESPACE:-fastapi-react}"
RELEASE="${RELEASE:-fastapi-react}"
KIND_CLUSTER="${KIND_CLUSTER:-fastapi-react}"

die() { echo "error: $*" >&2; exit 1; }

# Every script that touches a cluster calls this first. The local scripts must
# never run against EKS by accident: a stale kubeconfig context is the most
# common way a "local" command lands somewhere real.
require_local_context() {
  CONTEXT="$(kubectl config current-context 2>/dev/null)" \
    || die "no current kubectl context"
  case "$CONTEXT" in
    docker-desktop) CLUSTER_KIND=docker-desktop ;;
    kind-*)         CLUSTER_KIND=kind; KIND_CLUSTER="${CONTEXT#kind-}" ;;
    *) die "current context is '$CONTEXT', not a local cluster.
       kubectl config use-context docker-desktop   (or kind-$KIND_CLUSTER)" ;;
  esac
}
