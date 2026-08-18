# Production delivery and operations runbook

## Release path

1. Pull request: format/lint, unit tests, integration tests, dependency and container scans.
2. `main`: repeat tests; build and publish a single commit-SHA container artifact (GHCR before AWS, ECR after AWS); publish image metadata.
3. GitOps change: reference the exact immutable image digest in the regional manifest.
4. Argo Rollouts deploys 5% → 25% → 50% → 100%, pausing between steps. It aborts on elevated 5xx rate, latency, failed synthetic checks, or pod readiness failure.
5. Rollback: Argo Rollouts restores the last healthy ReplicaSet; retain the prior image digest and database migrations must be backward-compatible.

## Minimum alarms

- Regional public synthetic failure (two consecutive 5-minute runs).
- ALB 5xx rate, target unhealthy count, and p95 latency.
- EKS node/pod CPU and memory saturation; restart rate and pending pods.
- Aurora writer CPU, connections, free memory/storage, replication lag, failover event.
- WAF blocked-request anomaly and CloudTrail/IAM changes.
- Payment checkout provider 5xx/timeout rate, webhook signature failures, webhook age, paid-session reconciliation mismatch, refund/dispute events, and a drop to zero successful checkouts against normal traffic.
- Instagram webhook signature failures, webhook delivery age, Graph API 4xx/429/5xx rate, AutoDM retry depth, and dead-letter queue age.

Each critical alarm routes to an SNS topic connected to the on-call system. Validate paging with a controlled test after setup.

## External integration release gate

Keep both integrations disabled in a new stage. Load stage-specific values from AWS Secrets Manager through External Secrets, switch only to `test`, validate signed provider webhooks and a Razorpay test payment, then validate one allowlisted Instagram conversation initiated by the recipient. Promotion to `live` requires an approved change, provider account/KYC readiness, privacy and refund policies, webhook replay testing, reconciliation output, alarms, and a rollback that sets the mode back to `disabled` without removing evidence.

## GitHub Environment controls

Create three protected GitHub Environments: `dev`, `preprod`, and `prod`. Require one approver for preprod and two for prod, restrict prod deployment to `main`, and require a change-ticket value in the manual dispatch. The pipeline must never automatically promote a commit between stages.
