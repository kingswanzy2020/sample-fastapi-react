#!/bin/bash
# Validate the chart for every environment WITHOUT a cluster: helm lint, then
# helm template, then schema validation of the rendered manifests with
# kubeconform (run from its container image, so nothing to install).
#
# No cluster contact, no AWS contact. Safe to run anywhere, and what CI runs.

set -euo pipefail
# shellcheck source=scripts/k8s/lib.sh
source "$(dirname "$0")/lib.sh"

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.34.0}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# Dummy values: validation needs the required fields filled, not real ones.
local_args=(--set image.tag=sha-validate
            --set secrets.SECRET_KEY=validate --set secrets.POSTGRES_PASSWORD=validate)
eks_args=(--set image.tag=sha-validate
          --set image.registry=000000000000.dkr.ecr.us-east-1.amazonaws.com/fastapi-react-dev-k8s
          --set database.host=db.invalid
          --set externalSecret.dbSecretName=validate
          --set ingress.alb.certificateArn=validate)

declare -A envs=(
  [local]="-f $CHART/values-local.yaml"
  [ci]="-f $CHART/values-local.yaml -f $CHART/values-ci.yaml"
  [eks]="-f $CHART/values-eks.yaml"
)

for env in local ci eks; do
  if [ "$env" = eks ]; then args=("${eks_args[@]}"); else args=("${local_args[@]}"); fi
  # shellcheck disable=SC2086
  helm lint "$CHART" ${envs[$env]} "${args[@]}" --quiet
  # shellcheck disable=SC2086
  helm template "$RELEASE" "$CHART" -n "$NAMESPACE" ${envs[$env]} "${args[@]}" > "$out/$env.yaml"
  echo "✓ $env: lint + template ($(grep -c '^kind:' "$out/$env.yaml") objects)"
done

# The ExternalSecret and SecretStore schemas come from the community CRD catalog.
docker run --rm -v "$out:/rendered:ro" ghcr.io/yannh/kubeconform:v0.7.0 \
  -strict -summary \
  -kubernetes-version "$KUBERNETES_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  /rendered/local.yaml /rendered/ci.yaml /rendered/eks.yaml
