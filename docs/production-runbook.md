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

Each critical alarm routes to an SNS topic connected to the on-call system. Validate paging with a controlled test after setup.

## GitHub Environment controls

Create three protected GitHub Environments: `dev`, `preprod`, and `prod`. Require one approver for preprod and two for prod, restrict prod deployment to `main`, and require a change-ticket value in the manual dispatch. The pipeline must never automatically promote a commit between stages.
