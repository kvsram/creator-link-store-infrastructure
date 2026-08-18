# GitHub Actions to AWS

Use two separate short-lived OIDC roles. Never store an AWS access key or kubeconfig in GitHub.

## Build role

The existing Terraform `github-oidc` module creates an ECR-publish role for `main` in the frontend and backend repositories. It permits ECR authorization plus layer/image upload to `creator-link-store-*`. It does not grant EKS deployment.

Before enabling ECR publication, configure `AWS_ECR_ROLE_ARN`, target region, and repository URL as organization/repository variables, then add a tested ECR login/push step to the build workflows. Until then, `main` publishes immutable `sha-<commit>` images to GHCR.

The OIDC provider thumbprint and every pinned action/module version must be reviewed against current AWS/GitHub guidance before Terraform apply; checked-in values are snapshots.

## Deploy role and private runner

The manual frontend/backend deployment workflows require a different `AWS_DEPLOY_ROLE_ARN`. The current Terraform does not create this role yet. Its eventual permissions should be limited to `eks:DescribeCluster` for the selected stage clusters plus Kubernetes access entries/RBAC for only the `creator-store` namespace and required deployment objects.

Because the EKS API is private, register a Linux self-hosted runner inside the VPC or connected network with labels:

```text
self-hosted
linux
aws-private
```

Harden it as ephemeral/single-job infrastructure; restrict egress, patch its image, prevent untrusted fork workloads, and send runner audit logs to the security account. Pull-based GitOps is an alternative and avoids granting GitHub jobs direct cluster connectivity.

## Protected GitHub Environments

Create `dev`, `preprod`, and `prod`. Require reviewers for preprod/prod, restrict prod to `main`, and configure these variables per environment:

```text
AWS_DEPLOY_ROLE_ARN
AWS_REGION_A
AWS_REGION_B
AWS_REGION_C
EKS_CLUSTER_A
EKS_CLUSTER_B
EKS_CLUSTER_C
FRONTEND_IMAGE_REPOSITORY   # optional; defaults to GHCR
BACKEND_IMAGE_REPOSITORY    # optional; defaults to GHCR
```

The workflow resolves the selected logical region, assumes the role using OIDC, obtains an ephemeral EKS token with `aws eks update-kubeconfig`, applies the Kustomize overlay, sets the immutable SHA image, and waits for rollout health. Preprod/prod dispatches require a non-empty change ticket. A 40-character lowercase hexadecimal Git SHA is required.

## Required AWS work still missing

- deploy-role Terraform, Kubernetes access entries/RBAC, and stage/environment trust conditions;
- ECR publication and cross-region repository/replication design;
- ephemeral runner or GitOps controller provisioning;
- image signing/SBOM/provenance and admission verification;
- environment-specific host/certificate/Secret patches;
- rollout canary analysis and automatic rollback.

Do not enable the manual AWS workflows until those items are implemented and tested in dev.
