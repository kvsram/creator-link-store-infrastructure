terraform {
  required_version = ">= 1.10.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.expected_account_id]
}

data "aws_caller_identity" "current" {}

locals {
  operator_user_name   = "creator-store-operator"
  operator_group_name  = "CreatorStoreHumanOperators"
  deployment_role_name = "CreatorStoreEphemeralDeploymentOperator"
}

resource "aws_iam_user" "operator" {
  name          = local.operator_user_name
  path          = "/"
  force_destroy = false

  tags = {
    Project   = "creator-store"
    Purpose   = "ephemeral-test-operator"
    ManagedBy = "manual-bootstrap"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = data.aws_caller_identity.current.arn != "arn:aws:iam::${var.expected_account_id}:root"
      error_message = "Refusing to manage deployment identities with AWS root credentials. Sign in as a non-root principal and assume the deployment role with MFA."
    }
  }
}

resource "aws_iam_group" "human_operators" {
  name = local.operator_group_name
  path = "/"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_user_group_membership" "operator" {
  user = aws_iam_user.operator.name

  groups = [
    aws_iam_group.human_operators.name,
  ]
}

resource "aws_iam_group_policy_attachment" "change_password" {
  group      = aws_iam_group.human_operators.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

data "aws_iam_policy_document" "operator_self_service" {
  statement {
    sid    = "ViewAccountAndMFA"
    effect = "Allow"

    actions = [
      "iam:GetAccountPasswordPolicy",
      "iam:ListVirtualMFADevices",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ManageOwnIdentity"
    effect = "Allow"

    actions = [
      "iam:ChangePassword",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]

    resources = [
      "arn:aws:iam::${var.expected_account_id}:user/&{aws:username}",
    ]
  }

  statement {
    sid    = "CreateOwnMFA"
    effect = "Allow"

    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]

    resources = [
      "arn:aws:iam::${var.expected_account_id}:mfa/&{aws:username}",
    ]
  }

  statement {
    sid    = "AssumeDeploymentRole"
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    resources = [
      "arn:aws:iam::${var.expected_account_id}:role/${local.deployment_role_name}",
    ]
  }
}

resource "aws_iam_group_policy" "operator_self_service" {
  name   = "CreatorStoreOperatorSelfService"
  group  = aws_iam_group.human_operators.name
  policy = data.aws_iam_policy_document.operator_self_service.json
}

data "aws_iam_policy_document" "deployment_role_trust" {
  statement {
    sid     = "MFAProtectedOperator"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.operator.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "deployment_operator" {
  name                 = local.deployment_role_name
  path                 = "/"
  description          = "Temporary Terraform and EKS operator for creator-store ephemeral testing"
  max_session_duration = 14400
  assume_role_policy   = data.aws_iam_policy_document.deployment_role_trust.json

  tags = {
    Project     = "creator-store"
    Purpose     = "ephemeral-test-deployment"
    ManagedBy   = "manual-bootstrap"
    ReviewAfter = "2026-09-15"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "temporary_administrator" {
  role       = aws_iam_role.deployment_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
