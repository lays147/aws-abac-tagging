# The `sub` claim (repo:<org>/<repo>:ref:refs/heads/<branch>) is available in
# the role session (see AWS's OIDC federation condition key docs), so it can
# be compared directly against a resource tag using a StringLike policy
# variable - matching the calling repository's name against the bucket's
# Application tag without needing a second role or session tags.
# Both the org and repo name segments carry a wildcard suffix because GitHub
# appends an immutable numeric ID to each (e.g.
# repo:lays147@7799231/my-repo@123:ref:...).
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
      values   = ["repo:${local.github_org}*/$${aws:ResourceTag/Application}*:*"]
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
      values   = ["repo:${local.github_org}*/$${aws:ResourceTag/Application}*:*"]
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
