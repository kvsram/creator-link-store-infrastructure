# Production delivery and operations runbook

## Current release capability

1. Infrastructure pull request: Terraform format/validation and filesystem policy gates run independently of application CI.
2. Infrastructure plan: an operator selects a protected stage and exact infrastructure commit; the workflow assumes the stage infra role and saves a reviewable plan.
3. Infrastructure apply: after plan/change approval, a separate workflow replans and applies the same immutable commit, then publishes/verifies the SSM infrastructure-release marker.
4. Application pull request: backend verification or frontend build plus filesystem vulnerability scan.
5. Application `main`: build/test and publish an immutable `sha-<commit>` GHCR image plus build artifact. This does not provision or deploy anything.
6. Application dispatch: an approved operator supplies stage, logical region, exact application SHA, required applied infrastructure SHA, and change ticket for preprod/prod.
7. A private self-hosted runner assumes the deploy role, verifies the infrastructure marker, resolves the EKS/ECR/DB contract from SSM, copies the immutable image to environment ECR, applies Kustomize, and waits for rollout health.
8. Stop/rollback: remove regional traffic when impact is active, then deploy the previously proven image SHA or use `kubectl rollout undo` only after checking database compatibility.

The active workflows are described in [Infrastructure-first releases](release-architecture.md). No AWS plan or apply has been run yet.

The current repository does **not** include Argo Rollouts, automated 5/25/50/100 canary steps, metric analysis, or an automatic rollback controller. Those are target capabilities below, not current claims.

## Target canary release

Before production, install and own a rollout controller (or implement equivalent weighted ALB target groups), define analysis templates, and test:

1. deploy canary at 5%;
2. run API/public-store synthetic and compare 5xx, latency, saturation, and checkout/webhook safety metrics;
3. pause for operator/automated judgment;
4. advance through 25%, 50%, and 100%;
5. abort and restore the previous immutable digest when thresholds fail.

Database migrations must be backward compatible through the whole rollout and rollback window. Separate destructive cleanup into a later release after the old version can no longer run.

## Pre-deployment record

Record stage, region, change ticket, applied infrastructure SHA, frontend/backend image digests, application source SHAs, schema migration version, config change, secret version identifiers (never values), expected metrics, canary duration, previous healthy digest, rollback owner, and customer-impact window.

## Minimum alarms

- regional public synthetic failure (two consecutive five-minute runs);
- ALB 5xx rate, target unhealthy count, request volume anomaly, and p95/p99 latency;
- EKS node/pod CPU and memory saturation, restart rate, pending/unschedulable Pods, and HPA ceiling;
- database writer CPU, connections, free memory/storage, replication lag, failover event, backup failure, and connection exhaustion;
- WAF block anomaly, GuardDuty/Security Hub critical finding, and sensitive CloudTrail/IAM changes;
- payment provider 5xx/timeout, webhook signature failure, oldest unprocessed webhook, paid-session reconciliation mismatch, refunds/disputes, and unexpected zero-success intervals;
- Instagram webhook signature failure, delivery age, Graph API 4xx/429/5xx, retry/dead-letter depth, and unexpected send volume.

Each critical alarm needs an owner, severity, threshold rationale, dashboard/runbook link, deduplication key, and tested SNS/on-call receiver. The existing Terraform creates only a log group, a dashboard shell, and an alarm referring to a future canary; it does not yet create a functioning Synthetics canary or paging route.

## External integration release gate

Keep payments and Instagram disabled in every new stage. Load stage-specific values from AWS Secrets Manager through External Secrets, switch only one integration to `test`, and prove:

- invalid webhook signatures are rejected;
- duplicate valid webhooks are harmless;
- a Razorpay test order uses paise and reconciles to one local checkout/order transition;
- provider timeouts do not mark an order paid;
- one Instagram allowlisted conversation, initiated by the recipient, can receive a confirmed test message;
- disabling the mode stops new external effects while preserving evidence.

Promotion to `live` additionally requires provider/KYC readiness, privacy/terms/refund policies, data-retention approval, refund/dispute and reconciliation operations, capacity/rate-limit tests, alarms, and an approved change.

## Regional failure

1. Confirm user impact from independent synthetics and regional service metrics.
2. Stop automated promotion and external side-effect jobs in the failing region.
3. Remove or reduce Route 53 traffic only after confirming the destination region is healthy and has the correct data role/capacity.
4. Never direct writes to a database read replica. Promote/fail over the database using its reviewed runbook first, then update verified connection secrets/endpoints.
5. Validate login, public store, a non-charging checkout readiness path, provider webhook reachability, and background queues.
6. Record recovery timing and reconcile provider/order events after service restoration.

## GitHub Environment controls

Use protected `dev`, `preprod`, and `prod` Environments. Require at least one reviewer for preprod and two for prod, restrict prod to `main`, and require a change ticket in the manual dispatch. The pipeline never automatically promotes a commit between stages.
