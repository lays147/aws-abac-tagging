output "role_arn" {
  description = "ARN of the generic GitHub OIDC-trusted role. Any repo in the org can assume it directly; the S3 sync policy scopes access per-repo via the ABAC condition."
  value       = aws_iam_role.this.arn
}
