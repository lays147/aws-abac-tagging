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

  # GitHub's OIDC `sub` claim's trailing segment depends on whether the
  # calling job sets `environment:` - if it does (ours all do, so the
  # environment claim below is populated for policies.tf), `sub` ends in
  # `:environment:<name>` instead of `:ref:<ref>`. `ref` and `environment`
  # are still available as their own separate, independently-populated
  # condition keys regardless of that (see AWS's OIDC federation condition
  # key docs), so ref restriction is expressed as its own StringLike
  # condition (allowed_refs) rather than folded into the sub pattern.
  allowed_environment = local.is_production ? "production" : "default"

  # Production releases are cut as git tags, so the `production` workspace
  # only trusts tag refs (any refs/tags/*, since a tag ref alone can't tell
  # which branch it was cut from). Every other workspace only trusts pushes
  # to main or master.
  allowed_refs = local.is_production ? (
    ["refs/tags/*"]
    ) : (
    [
      "refs/heads/main",
      "refs/heads/master",
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
