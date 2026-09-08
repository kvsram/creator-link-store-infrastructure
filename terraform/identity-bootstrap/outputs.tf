output "operator_user_arn" {
  description = "ARN of the human deployment operator."
  value       = aws_iam_user.operator.arn
}

output "deployment_role_arn" {
  description = "MFA-protected role that Terraform and EKS administration use."
  value       = aws_iam_role.deployment_operator.arn
}

output "access_review_due" {
  description = "Date by which the temporary AdministratorAccess attachment must be reviewed."
  value       = aws_iam_role.deployment_operator.tags["ReviewAfter"]
}
