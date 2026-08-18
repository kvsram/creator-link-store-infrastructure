# Production delivery and operations runbook

## Current release capability

1. Pull request: backend verification or frontend build plus filesystem vulnerability scan.
2. `main`: build/test and publish an immutable `sha-<commit>` GHCR image plus build artifact.
3. Manual dispatch: an approved operator chooses stage, logical region, exact 40-character SHA, and change ticket for preprod/prod.
4. A private self-hosted runner assumes an AWS role with OIDC, applies Kustomize, replaces the Deployment image, and waits for Kubernetes rolling-rollout health.
5. Stop/rollback: remove regional traffic when impact is active, then use the previously proven image SHA (preferred explicit promotion) or `kubectl rollout undo` only after checking database compatibility.

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

Record stage, region, change ticket, frontend/backend image digests, source SHAs, schema migration version, config change, secret version identifiers (never values), expected metrics, canary duration, previous healthy digest, rollback owner, and customer-impact window.

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
