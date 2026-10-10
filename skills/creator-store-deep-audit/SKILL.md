---
name: creator-store-deep-audit
description: Coordinate evidence-based, multi-agent audits of Creator Store releases when evaluating production readiness, CI/CD, architecture, security, UI and device behavior, load, resilience, or product gaps. Use for repository-plus-live-environment deep testing, not an ordinary one-file code review.
---

# Creator Store Deep Audit

Produce an auditable release verdict, not a long unverified suggestion list. Inspect the exact source, artifact, infrastructure release, and reachable environment, then coordinate six independent specialist reviews and consolidate their evidence.

## Safety and truth rules

- Ask for or discover the target environment, repository refs, deployed image digests, infrastructure release, allowed test accounts/data, permitted mutations, external-provider modes, and load-test budget.
- If authorization or a safe test environment is missing, continue with read-only checks and mark active tests `BLOCKED`; never silently run local builds/tests that write artifacts or data, test production load, exploit a live target, charge money, send real DMs/email, or use personal data.
- Never request or expose passwords, OTPs, session cookies, API keys, payment details, provider tokens, or secret values. Let the human enter credentials and MFA.
- Label every conclusion `VERIFIED`, `INFERRED`, `PROPOSED`, or `BLOCKED`. A passing build, HTTP 200, Terraform file, or rendered screen is not end-to-end proof.
- Tie evidence to an exact commit, image digest, environment, URL, UTC timestamp, test input class, and observed result. Redact sensitive values.
- Test tenant isolation with synthetic accounts. Do not use the public `alex` demo as an authenticated account.
- Preserve repository boundaries and protected branches. Reviews do not authorize merges, deployments, cloud purchases, or provider activation.

## Workflow

### 1. Freeze the release identity

Capture:

1. frontend, backend, and infrastructure repository URLs plus exact commits;
2. built image digests and provenance available for those commits;
3. environment, region, infrastructure release marker, database migration version, and public origin;
4. current feature-parity document and known provider/test limitations;
5. rollback candidate and cleanup/expiry deadline.

If an identifier is unavailable, emit `release_identity_status: PARTIAL`, list each missing field, and limit conclusions to evidence that remains attributable. If local source and deployed artifacts cannot be mapped, emit `release_identity_status: MISMATCH` and stop active testing; the overall verdict is `BLOCKED`. Read [project baseline](references/project-baseline.md) for this project's known topology, but verify it because the dated snapshot can become stale.

### 2. Define scope and success criteria

Write explicit functional journeys, security boundaries, supported devices, SLO targets, recovery objectives, data-retention expectations, and release gates. Use [test matrix](references/test-matrix.md) to select only applicable tests.

### 3. Run six independent lanes

Give each specialist the same release manifest and scope, but only its assigned lane. Use the paste-ready prompts in [agent prompts](references/agent-prompts.md):

1. functional/API/database integrity;
2. frontend UX, accessibility, browser, and device behavior;
3. security, privacy, and abuse resistance;
4. performance, capacity, resilience, and distributed-systems behavior;
5. CI/CD, IaC, software supply chain, observability, and operations;
6. product completeness and external integrations.

Do not let agents call a planned capability implemented. Each must return evidence using [report contract](references/report-contract.md).

Use fresh contexts for all lanes. Retry a lane once only for a transient tool failure; do not replace a dissenting result with another model run. The coordinator may summarize completed lanes when one is missing, but must mark the missing lane `BLOCKED` and cannot issue `PRODUCTION_CANDIDATE`. If fewer than four lanes finish, issue only a partial report with overall verdict `BLOCKED`.

### 4. Execute gates from cheapest to riskiest

Run in this order unless the target requires a stricter sequence:

1. repository and release-manifest consistency;
2. static checks, unit tests, component tests, contract tests, IaC validation, and policy checks;
3. isolated local integration tests with a clean database;
4. staged browser/API end-to-end tests with synthetic data;
5. authorized security scanning and negative tests;
6. authorized baseline/load/soak/failure tests in a disposable or production-like stage;
7. rollback, restore, and operational-response drills.

Stop a lane when its safety boundary, error budget, cost budget, or data-integrity limit is reached. Record partial evidence rather than retrying destructively.

### 5. Consolidate without averaging away blockers

Use the coordinator prompt in [agent prompts](references/agent-prompts.md). Deduplicate findings by violated invariant and affected release. Resolve contradictions against primary evidence. One critical tenant-isolation, data-loss, secret-exposure, payment-integrity, or rollback failure is a release blocker even if five other lanes pass.

### 6. Issue a decision

Use one verdict:

- `NO_GO`: a release-blocking defect is verified.
- `BLOCKED`: required evidence could not be collected safely.
- `TEST_ONLY`: suitable only for synthetic testing under documented limitations.
- `CONDITIONAL`: applicable gates passed, with named conditions before the next stage.
- `PRODUCTION_CANDIDATE`: all required functional, security, performance, reliability, operational, and rollback gates passed for the declared scale. This is not a permanent certification.

Apply precedence deterministically:

1. release identity mismatch or fewer than four completed lanes -> `BLOCKED`;
2. verified P0/P1 release blocker -> `NO_GO`;
3. required lane/evidence unavailable -> `BLOCKED`;
4. safely functioning only under declared synthetic/test limitations -> `TEST_ONLY`;
5. applicable gates passed with named prerequisites before the next stage -> `CONDITIONAL`;
6. all declared production gates passed -> `PRODUCTION_CANDIDATE`.

Return a prioritized roadmap with owner role boundary, dependency, acceptance test, rollback, and target stage for every P0/P1 item. Do not invent individual owners when an ownership roster is absent. Use [maturity model](references/maturity-model.md) when comparing the result with large-company practices or deciding whether to split services.

## Required deliverables

- release manifest and environment map;
- implemented/partial/missing/blocked capability matrix;
- six specialist reports and evidence index;
- deduplicated P0-P3 findings;
- current architecture classification and scale bottlenecks;
- release verdict with explicit reasons;
- 30/60/90-day implementation and validation plan;
- retest list that maps every fix to a deterministic check.
