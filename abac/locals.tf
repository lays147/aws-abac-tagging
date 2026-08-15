locals {
  name               = "github-actions"
  region             = "us-east-1"
  github_oidc_domain = "token.actions.githubusercontent.com"


  github_org = "lays147"
  reponame   = "repo:${local.github_org}/*"

  tags = {
    "Environment" = terraform.workspace
    "Application" = "github-actions"
    "Team"        = "platform"
    "CostCenter"  = "foundation"
    "ManagedBy"   = "Terraform"
  }
}
