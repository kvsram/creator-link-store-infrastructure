# Disposable EKS + RDS feature-test environment

This root creates a deliberately short-lived AWS test stack in `us-east-2`:

- one EKS cluster in standard support;
- one public, on-demand `t3a.medium` managed worker;
- the worker, its gp3 upload volume, and RDS are pinned to the same Availability Zone;
- one private, Single-AZ `db.t4g.micro` PostgreSQL instance;
- no NAT Gateway, load balancer, domain, ACM certificate, WAF, ECR, or paid log ingestion;
- no customer-managed EKS KMS key; EKS 1.35 uses its default AWS-owned at-rest encryption;
- one private gp3-backed upload PVC created later by the Kubernetes overlay;
- Standard-tier SSM parameters for runtime configuration.

The expiration guard uses the Terraform plan timestamp and rejects plans whose teardown deadline is more than 168 hours away. Tags and the SSM `/expires-at` value are reminders; they do not automatically destroy resources. The operator must run the reviewed destroy plan by the deadline.

## Required safety checks

1. Copy `backend.hcl.example` to an untracked `backend.hcl`, set the bucket created by `terraform/bootstrap-ephemeral`, and keep the isolated state key.
2. Set `expected_account_id`, set `operator_role_arn` to a non-root IAM role in that account, and replace both example CIDRs with approved `/32` addresses.
3. Verify EKS 1.35 is still in standard support in `us-east-2` immediately before planning.
4. Confirm the plan contains exactly one `t3a.medium` worker in the first public subnet, one Single-AZ `db.t4g.micro` RDS instance in the matching AZ, zero NAT Gateways, and zero load balancers.
5. Confirm EKS worker root volumes and EBS CSI-created upload volumes carry the `TestId` and `ExpiresAt` tags used during cleanup verification.
6. Apply only after the account, credit expiration, plan cost, and teardown time have been reviewed.
7. Never use real customer, payment, or Instagram credentials in this HTTP-only environment.

Initialize with the reviewed backend configuration:

```bash
terraform init -backend-config=backend.hcl
```

## Teardown

Delete the `creator-store` namespace first so the EBS CSI controller can remove the upload volume. Then create and review a Terraform destroy plan using the exact same backend key and variables. Apply only that reviewed plan, then verify that EKS, RDS, EC2, EBS, ENIs, security groups, SSM parameters, and the test VPC are gone.
