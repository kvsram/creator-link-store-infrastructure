# AWS ephemeral overlay

This overlay is only for the short-lived EKS/RDS feature test. It exposes the frontend through NodePort `30080`, keeps the backend internal, uses one replica per application, and stores uploads on one encrypted gp3 EBS volume.

Render through `scripts/deploy-aws-ephemeral.sh`; the source YAML deliberately contains placeholders rather than credentials or mutable image tags. Only disposable test accounts are allowed because the endpoint uses HTTP.
