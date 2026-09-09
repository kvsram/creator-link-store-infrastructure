# Disposable K3s + RDS feature-test environment

This root creates the approved, short-lived AWS test stack in `us-east-2`:

- one public `t3a.medium` Amazon Linux 2023 instance running pinned K3s;
- one stable Elastic IP on HTTP port `80`, restricted to approved IPv4 `/32` addresses by default;
- an explicit `enable_public_http = true` test mode that opens only port `80` to `0.0.0.0/0`;
- an internal NodePort `30080` retained for node-local health verification;
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
2. Set `expected_account_id`. Keep `enable_public_http = false` and replace the example source with current tester IPv4 `/32` addresses unless public testing has been explicitly approved. For that case only, set `enable_public_http = true`; Terraform then ignores `tester_cidrs` and creates exactly one `0.0.0.0/0` ingress rule on port `80`.
3. Confirm the plan has exactly one `t3a.medium`, one Elastic IP, one encrypted 40 GiB gp3 root volume, and one private Single-AZ `db.t4g.micro` with 20 GiB encrypted gp3.
4. Confirm the plan has zero EKS resources, NAT Gateways, and load balancers. In allowlist mode, confirm only approved `/32` ingress on port `80`. In explicit public mode, confirm exactly one `0.0.0.0/0` ingress rule and that it is only for port `80`. Never expose ports `22`, `6443`, or `30080`.
5. Apply only from the expected non-root role after reviewing the account, cost, exact infrastructure commit, and teardown deadline.
6. Use only synthetic credentials and test data because the public endpoint is HTTP-only.

Public mode makes the landing page reachable from any IPv4 address. Application-level Nginx rate limits still apply by client IP, but they do not replace TLS, an AWS edge service, or managed DDoS protection. Do not use real credentials, payment data, or customer information in this environment.

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
- The endpoint is HTTP-only and restricted by default. Explicit public mode is for synthetic testing only. Purchase a domain and add TLS before real users or real credentials.
- The smoke suites create synthetic database records and must run only in this disposable environment.
