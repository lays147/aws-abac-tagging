# The `sub` claim is available in the role session (see AWS's OIDC federation
# condition key docs - it's the only GitHub claim marked "Available in
# session: Yes"), so it can be compared directly against resource tags using
# a StringLike policy variable - no session tags or role-chaining needed.
# Both the org and repo name segments carry a wildcard suffix because GitHub
# appends an immutable numeric ID to each (e.g.
# repo:lays147@7799231/my-repo@123:...).
#
# `ref` and `environment` are NOT session-available on their own (see
# abac/role.tf's comment), so they can't be used as separate condition keys
# here. But every job in this repo's workflow sets `environment:`, which
# means GitHub puts the environment name directly into `sub`'s suffix as
# `:environment:<name>` (instead of `:ref:<ref>`, which only appears when a
# job has no `environment:`) - see the CloudTrail principalId this pattern
# was derived from:
#   repo:lays147@<id>/aws-abac-tagging@<id>:environment:default
# So the environment can be enforced here too, by extending the `sub`
# pattern to require that suffix match the bucket's Environment tag as a
# second policy variable in the same StringLike condition. This only works
# because every job declares `environment:` - a job that didn't would get
# a `:ref:...` suffix instead and always fail this pattern (fail closed).
data "aws_iam_policy_document" "s3_sync" {
  statement {
    sid    = "SyncObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::*/*"]
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_domain}:sub"
      values   = ["repo:${local.github_org}*/$${aws:ResourceTag/Application}*:environment:$${aws:ResourceTag/Environment}"]
    }
  }

  statement {
    sid       = "ListMatchingBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::*"]
    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_domain}:sub"
      values   = ["repo:${local.github_org}*/$${aws:ResourceTag/Application}*:environment:$${aws:ResourceTag/Environment}"]
    }
  }
}

# NOTE: aws:ResourceTag conditions on bucket-level actions (ListBucket above)
# only evaluate once bucket-level ABAC is enabled on the target bucket via
# PutBucketAbac (s3:PutBucketAbac) - see my-demo-bucket/bucket.tf. Object-level
# actions (PutObject/GetObject/DeleteObject) evaluate aws:ResourceTag against
# the bucket's tags without needing that flag.
resource "aws_iam_policy" "s3_sync" {
  name   = "${local.name}-s3-sync"
  policy = data.aws_iam_policy_document.s3_sync.json
}

resource "aws_iam_role_policy_attachment" "s3_sync" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.s3_sync.arn
}
