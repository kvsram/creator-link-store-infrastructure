# Disposable K3s + RDS feature-test environment

This root creates the approved, short-lived AWS test stack in `us-east-2`:

- one public `t3a.medium` Amazon Linux 2023 instance running pinned K3s;
- one stable Elastic IP and NodePort `30080`, restricted to approved IPv4 `/32` addresses;
- no SSH ingress and no public Kubernetes API;
- a 40 GiB encrypted gp3 root disk, including K3s `local-path` upload storage;
- one private, encrypted, Single-AZ `db.t4g.micro` PostgreSQL 16 instance;
- one public subnet for K3s and two private subnets across two AZs for the RDS subnet group;
- Standard-tier SSM parameters and SSM Run Command for administration;
- no EKS, NAT Gateway, load balancer, domain, TLS certificate, WAF, paid KMS key, or paid log ingestion.

The VPC is `10.42.0.0/16`. K3s is explicitly configured with pod CIDR
`10.244.0.0/16`, service CIDR `10.245.0.0/16`, and DNS `10.245.0.10` so the
networks cannot overlap.

The expiration guard rejects a plan whose teardown deadline is in the past or
more than 168 hours away. Tags and the SSM `/expires-at` parameter are reminders,
not an automatic deletion mechanism. The operator must destroy the stack by that
deadline.

## Required safety checks

1. Copy `backend.hcl.example` to untracked `backend.hcl` and use the isolated S3 state bucket created by `terraform/bootstrap-ephemeral`.
2. Set `expected_account_id`; replace the example source with the current CloudShell and tester IPv4 `/32` addresses; never use `0.0.0.0/0`.
3. Confirm the plan has exactly one `t3a.medium`, one Elastic IP, one encrypted 40 GiB gp3 root volume, and one private Single-AZ `db.t4g.micro` with 20 GiB encrypted gp3.
4. Confirm the plan has zero EKS resources, NAT Gateways, and load balancers, and no ingress on ports `22` or `6443`.
5. Apply only from the expected non-root role after reviewing the account, cost, exact infrastructure commit, and teardown deadline.
6. Use only synthetic credentials and test data because the public endpoint is HTTP-only.

Initialize with the reviewed backend configuration:

```bash
terraform init -backend-config=backend.hcl
```

Deploy immutable application images from the exact committed checkout:

```bash
./scripts/deploy-aws-ephemeral.sh \
  devtest ACCOUNT_ID INFRA_SHA \
  BACKEND_SHA sha256:BACKEND_DIGEST \
  FRONTEND_SHA sha256:FRONTEND_DIGEST us-east-2
```

The operator-side script reaches the node only through SSM. Its node helper
retrieves the RDS password under `/creator-store/ephemeral/devtest/*` locally;
the password is never included in Run Command parameters or output.

## Verification and teardown

Run the complete read-only verification:

```bash
./scripts/verify-aws-ephemeral.sh \
  devtest ACCOUNT_ID INFRA_SHA \
  sha256:BACKEND_DIGEST sha256:FRONTEND_DIGEST us-east-2
```

Before teardown, review a Terraform destroy plan using the exact same state key
and variables. Apply only that saved destroy plan. Then run:

```bash
./scripts/verify-aws-ephemeral.sh --post-destroy devtest ACCOUNT_ID us-east-2
```

The post-destroy audit checks EC2, EBS, EIP, RDS, VPC networking, IAM, SSM,
load-balancer, NAT, and EKS scopes. It reports leftovers but never deletes them.

## Deliberate test limitations

- One K3s node and Single-AZ RDS have no high availability.
- `local-path` storage is on the root disk, has no hard 10 GiB quota, and is lost when the EC2 instance is replaced or destroyed.
- The endpoint is restricted HTTP. Purchase a domain and add TLS before real users or real credentials.
- The smoke suites create synthetic database records and must run only in this disposable environment.
