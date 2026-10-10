# Evidence and report contract

Every specialist must use this contract so a coordinator can merge reports without guessing.

## Required header

```yaml
lane: functional-api-data | frontend-device | security-privacy | performance-resilience | cicd-operations | product-integrations
auditor: <model/tool and version when known>
started_utc: <ISO-8601>
finished_utc: <ISO-8601>
environment: <local/dev/preprod/prod and region>
public_origin: <URL or none>
frontend_commit: <40-char SHA>
backend_commit: <40-char SHA>
infrastructure_commit: <40-char SHA>
applied_infrastructure_release: <40-char SHA or unavailable>
frontend_digest: <sha256 or unavailable>
backend_digest: <sha256 or unavailable>
database_migration_version: <version, NONE-startup-DDL, or unavailable>
artifact_provenance: <verified reference or unavailable>
scope: <read-only/static/staged-active/load/other>
test_input_class: <synthetic fixture/account/data profile; no secrets>
limitations: [<unavailable evidence or prohibited tests>]
```

If a release identifier is not known, say `UNKNOWN`; do not substitute the local branch head for the deployed release.

## Finding format

Use one block per independently fixable issue:

```yaml
id: LANE-001
title: <specific failed invariant>
status: VERIFIED | INFERRED | PROPOSED | BLOCKED
severity: P0 | P1 | P2 | P3
observed_at_utc: <ISO-8601>
category: <auth, data, UX, deployment, reliability, etc.>
affected_journey: <named user or operator flow>
environment: <where observed>
release_identity: <commits/digests>
preconditions: <synthetic state and permissions>
steps: [<minimal reproducible steps>]
expected: <observable requirement>
observed: <observable result>
evidence:
  - type: source | test | HTTP | browser | metric | log | cloud-state | document
    reference: <file:line, test name, redacted request id, screenshot, query, or URL>
impact: <customer/business/operational impact>
exploitability_or_frequency: <when applicable>
recommendation: <smallest safe correction>
acceptance_test: <deterministic proof of correction>
rollback: <how to reverse the correction>
owner_boundary: frontend | backend | data | platform | security | product | provider | human
```

Do not put credentials, full cookies, personal data, or secret request payloads in evidence.

## Severity

- `P0`: actively reproduced compromise/exposure, irreversible data loss, incorrect real-money state, or broad outage. Stop testing and escalate. A source-only authorization risk remains P1 until reproduced unless its independently verified impact already meets P0.
- `P1`: release blocker with likely severe customer impact, authentication/authorization bypass, no safe rollback, or core journey failure.
- `P2`: material defect with a workaround or limited scope; fix before broader availability.
- `P3`: quality, usability, maintainability, or optimization issue with low immediate impact.

Severity is impact and urgency, not how difficult the fix is.

## Lane summary

End each report with:

```yaml
tests_passed: [<named checks>]
tests_failed: [<finding IDs>]
tests_blocked: [<check and reason>]
untested_risks: [<risk>]
lane_verdict: PASS | FAIL | BLOCKED | CONDITIONAL
release_blockers: [<finding IDs>]
top_next_actions: [<ordered actions>]
```

## Coordinator output

The coordinator must preserve original finding IDs, list duplicates and contradictions, and produce:

1. release identity and whether it was verified;
2. declared scale/SLO/RTO/RPO and whether each was tested;
3. capability matrix: implemented, partial, missing, provider/human, blocked;
4. deduplicated P0-P3 findings;
5. current architecture and bottleneck diagram;
6. release verdict and exact blocking reasons;
7. ordered remediation plan with acceptance tests;
8. residual risk and deliberately deferred work.

Use owning role boundaries such as frontend, backend, data, platform, security, product, provider, or human operator. Never invent a person's name when no ownership roster was supplied.
