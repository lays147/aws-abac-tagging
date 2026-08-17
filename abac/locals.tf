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

  is_production = terraform.workspace == "production"

  # Restricts which git ref can assume the role, on top of the org/repo match
  # above. Production releases are cut as git tags, so the `production`
  # workspace only trusts tag refs (any refs/tags/*, since the sub claim
  # can't tell which branch a tag was cut from). Every other workspace only
  # trusts pushes to main or master.
  allowed_ref_subs = local.is_production ? (
    ["${local.reponame}:ref:refs/tags/*"]
    ) : (
    [
      "${local.reponame}:ref:refs/heads/main",
      "${local.reponame}:ref:refs/heads/master",
    ]
  )

  tags = {
    "Environment" = terraform.workspace
    "Application" = "github-actions"
    "Team"        = "platform"
    "CostCenter"  = "foundation"
    "ManagedBy"   = "Terraform"
  }
}
