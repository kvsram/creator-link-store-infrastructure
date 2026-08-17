# GitHub Actions to AWS

Set `AWS_REGION` and `AWS_ROLE_ARN` as GitHub Environment variables. The role is created by Terraform and permits only ECR image publishing. The application workflow must request `id-token: write`, assume that role, authenticate to ECR, and tag images with the immutable commit SHA.

Deployment is intentionally not granted to this role. EKS endpoints are private. Use Argo CD as a pull-based reconciler inside each cluster, or an AWS CodeBuild project running in private subnets. This keeps cluster-admin credentials out of GitHub.
