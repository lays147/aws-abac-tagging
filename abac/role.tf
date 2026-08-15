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
  }
}

# Single generic role, trusted by GitHub OIDC for the whole org. The `sub`
# claim is session-available (per AWS's OIDC federation condition key docs),
# so the S3 sync policy in policies.tf can compare it directly against the
# target bucket's Application tag via a StringLike policy variable - no
# role-chaining or session tagging required to get per-repo ABAC.
resource "aws_iam_role" "this" {
  name               = "${local.name}-assume-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}