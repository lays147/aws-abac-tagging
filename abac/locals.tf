locals {
  name               = "github-actions"
  region             = "us-east-1"
  github_oidc_domain = "token.actions.githubusercontent.com"


  github_org = "lays147"
  # GitHub OIDC tokens append an immutable numeric ID to the org/repo names
  # in the `sub` claim (e.g. repo:lays147@7799231/my-repo@123:ref:...), so the
  # org segment needs a wildcard after the name to tolerate the optional
  # "@<id>" suffix.
  reponame = "repo:${local.github_org}*/*"

  tags = {
    "Environment" = terraform.workspace
    "Application" = "github-actions"
    "Team"        = "platform"
    "CostCenter"  = "foundation"
    "ManagedBy"   = "Terraform"
  }
}
