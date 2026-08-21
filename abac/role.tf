data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "Github"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.default.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_domain}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_domain}:sub"
      values   = [local.reponame]
    }
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_domain}:ref"
      values   = local.allowed_refs
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_domain}:environment"
      values   = [local.allowed_environment]
    }
  }
}

# Single generic role, trusted by GitHub OIDC for the whole org, restricted
# per environment to either tag refs (production) or main/master pushes
# (non-production) via the independent `ref` claim, and to the matching
# GitHub Environment name via the `environment` claim - see
# local.allowed_refs / local.allowed_environment. All three conditions
# (sub, ref, environment) are ANDed since they're in the same statement.
# The `sub` claim is session-available (per AWS's OIDC federation condition
# key docs), so the S3 sync policy in policies.tf can compare it directly
# against the target bucket's Application tag via a StringLike policy
# variable - no role-chaining or session tagging required to get
# per-repo ABAC.
resource "aws_iam_role" "this" {
  name               = "${local.name}-assume-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}