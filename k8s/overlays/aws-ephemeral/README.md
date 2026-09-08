# AWS ephemeral K3s overlay

This overlay is only for the short-lived, single-node K3s/RDS feature test. It
exposes the frontend through NodePort `30080`, keeps the backend internal, uses
one replica per application, and stores uploads with K3s's built-in
`local-path` provisioner on the encrypted EC2 root disk.

Render and apply through `scripts/deploy-aws-ephemeral.sh`. The checked-in YAML
contains placeholders instead of credentials or mutable image tags; the SSM
node helper replaces them only with exact image digests and the Terraform
public origin. Use only synthetic test credentials because this endpoint is
restricted HTTP.
