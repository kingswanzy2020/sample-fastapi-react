# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name. ../platform looks the cluster up by this name."
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "irsa_role_arns" {
  description = "IAM roles for the in-cluster controllers."
  value       = module.eks.irsa_role_arns
}

output "kms_key_arn" {
  description = "KMS key encrypting Kubernetes Secrets in etcd."
  value       = module.eks.kms_key_arn
}

# ---------------------------------------------------------------------------
# Registry, secrets, database
# ---------------------------------------------------------------------------

output "ecr_registry_prefix" {
  description = "image.registry for the chart: images are <prefix>/backend and <prefix>/frontend."
  value       = module.ecr.registry_prefix
}

output "set_app_secret_command" {
  description = "Run once per session, before the first deploy. The value never enters Terraform state."
  value       = <<-EOT
    aws secretsmanager put-secret-value \
      --secret-id ${aws_secretsmanager_secret.app.arn} \
      --region ${var.aws_region} \
      --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\"}"
  EOT
}

output "db_endpoint" {
  description = "RDS endpoint."
  value       = module.database.endpoint
}

# The account-specific values the chart needs, as --set flags, so that
# values-eks.yaml in git carries no account ID, ARN or hostname.
output "helm_set_flags" {
  description = "Pass to helm: helm upgrade ... -f values-eks.yaml $(terraform output -raw helm_set_flags)"
  value = join(" ", [
    "--set image.registry=${module.ecr.registry_prefix}",
    "--set database.host=${module.database.address}",
    "--set externalSecret.dbSecretName=${module.database.master_user_secret_arn}",
  ])
}

# ---------------------------------------------------------------------------
# Cost and runbook
# ---------------------------------------------------------------------------

output "cost_per_hour" {
  description = "Approximate on-demand cost of this environment while it exists."
  value       = "~$0.30-0.35/h: EKS $0.10 + 2x t3.medium ~$0.08 + NAT ~$0.05 + ALB ~$0.03 + RDS ~$0.02 + IPv4 ~$0.02. Destroy the same day."
}

output "next_steps" {
  description = "Everything left to do after a successful apply."
  value       = <<-EOT

    ── Cluster is up. The meter is running (~$0.30-0.35/h). ───────────────

    1. KUBECTL
         aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
         kubectl get nodes -L topology.kubernetes.io/zone     # 2 nodes, 2 zones

    2. SET THE APP SECRET  (value never enters Terraform state)
         aws secretsmanager put-secret-value \
           --secret-id ${aws_secretsmanager_secret.app.arn} --region ${var.aws_region} \
           --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\"}"

    3. PLATFORM ADD-ONS  (AWS Load Balancer Controller, External Secrets Operator)
         cd ../platform && terraform init -backend-config=backend.hcl && terraform apply

    4. PUSH IMAGES  (from the repo root; ECR was created empty this session)
         ${module.ecr.docker_login_command}
         TAG=sha-$(git rev-parse HEAD)
         docker build -t ${module.ecr.registry_prefix}/backend:$TAG  ./backend
         docker build -t ${module.ecr.registry_prefix}/frontend:$TAG --target production ./frontend
         docker push ${module.ecr.registry_prefix}/backend:$TAG
         docker push ${module.ecr.registry_prefix}/frontend:$TAG

    5. DEPLOY THE CHART  (from the repo root)
         helm upgrade --install fastapi-react deploy/helm/fastapi-react \
           -f deploy/helm/fastapi-react/values-eks.yaml \
           $(terraform -chdir=terraform/environments/dev-k8s/cluster output -raw helm_set_flags) \
           --set image.tag=$TAG \
           -n fastapi-react --create-namespace --atomic --wait --timeout 10m

    6. VALIDATE  -- docs/ARCHITECTURE.md §22.5

    ── Tear down, in this order (§22.6) ───────────────────────────────────

         helm uninstall fastapi-react -n fastapi-react   # the controller deletes the ALB
         kubectl get ingress -A                          # wait until empty
         cd ../platform && terraform destroy
         cd ../cluster  && terraform destroy
  EOT
}
