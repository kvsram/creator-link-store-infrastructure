# AWS identity bootstrap

This Terraform root adopts and then manages the human identity used for the
creator-store disposable AWS environment. The resources were initially created
once through the AWS console because Terraform needed a safe non-root identity
before it could manage anything else.

It manages:

- IAM user `creator-store-operator` (without its console login profile,
  password, access keys, or MFA device)
- IAM group `CreatorStoreHumanOperators` and the user's membership
- AWS-managed `IAMUserChangePassword` group attachment
- inline group policy `CreatorStoreOperatorSelfService`
- MFA-protected role `CreatorStoreEphemeralDeploymentOperator`
- the role's temporary AWS-managed `AdministratorAccess` attachment

The user, group, and role have `prevent_destroy`. The operator user has
`force_destroy = false`. These safeguards make an accidental identity teardown
fail rather than silently deleting credentials or MFA configuration.

## Security boundary

Do not add passwords, access keys, MFA seeds, QR codes, session tokens, or
Terraform credentials to this directory. Terraform intentionally does not
manage `aws_iam_user_login_profile`, `aws_iam_access_key`, or
`aws_iam_virtual_mfa_device` resources.

The role trust policy names only `creator-store-operator` and requires
`aws:MultiFactorAuthPresent = true`. Its maximum session is four hours. The
`AdministratorAccess` attachment is temporary and the role is tagged
`ReviewAfter=2026-09-15`; replace it with least-privilege permissions after the
ephemeral deployment has been proven.

The self-service policy deliberately permits the operator to create only the
virtual MFA ARN `mfa/creator-store-operator`. When enrolling an authenticator
app, enter **`creator-store-operator`** as the AWS MFA device name. The friendly
label stored in the authenticator app can be anything. After first enrolling
MFA, sign out and sign in again with an MFA code before assuming the deployment
role; the console session that existed before enrollment is not MFA-authenticated.

## Adopt the existing resources

Run these commands only after `terraform/bootstrap-ephemeral` has created the
protected state bucket, and only from an MFA-authenticated, non-root AWS session
in the expected account. Never run them with the root account. Copy the example
file and replace its placeholder account ID locally; real `*.tfvars`, backend
configuration files, plans, and state files must stay outside the repository.

```bash
cd terraform/identity-bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init -reconfigure \
  -backend-config=/tmp/creator-store-identity-backend.hcl
aws sts get-caller-identity
```

The untracked backend file should use a distinct identity-state key:

```hcl
bucket       = "creator-store-tfstate-ACCOUNT_ID-us-east-2"
key          = "creator-link-store/identity/bootstrap.tfstate"
region       = "us-east-2"
encrypt      = true
use_lockfile = true
```

Before continuing, verify that `Arn` is not the account root ARN and that
`Account` exactly matches `expected_account_id`.

Import every already-existing resource before any apply:

```bash
terraform import -var-file=terraform.tfvars aws_iam_user.operator creator-store-operator
terraform import -var-file=terraform.tfvars aws_iam_group.human_operators CreatorStoreHumanOperators
terraform import -var-file=terraform.tfvars aws_iam_user_group_membership.operator 'creator-store-operator/CreatorStoreHumanOperators'
terraform import -var-file=terraform.tfvars aws_iam_group_policy_attachment.change_password 'CreatorStoreHumanOperators/arn:aws:iam::aws:policy/IAMUserChangePassword'
terraform import -var-file=terraform.tfvars aws_iam_group_policy.operator_self_service 'CreatorStoreHumanOperators:CreatorStoreOperatorSelfService'
terraform import -var-file=terraform.tfvars aws_iam_role.deployment_operator CreatorStoreEphemeralDeploymentOperator
terraform import -var-file=terraform.tfvars aws_iam_role_policy_attachment.temporary_administrator 'CreatorStoreEphemeralDeploymentOperator/arn:aws:iam::aws:policy/AdministratorAccess'
```

Then verify adoption without changing AWS:

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=terraform.tfvars -detailed-exitcode
```

The desired result is exit code `0` and **No changes**. Exit code `2` means
Terraform found drift; review every proposed change before applying it. Never
apply a plan that replaces or destroys the operator user, group, role, group
membership, MFA protection, or policy attachments.

## Future changes

Commit and review an infrastructure pull request first. After approval, assume
the deployment role with MFA, generate a saved plan, review it, and apply that
exact plan. Application releases happen only after their required
infrastructure release succeeds.
