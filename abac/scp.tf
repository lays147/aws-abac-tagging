# Denies creation of untagged resources so the ABAC policy tag set
# (CostCenter, Team, Application, Environment) is enforced org-wide, not just
# by convention. Uses "Null" conditions to check tag presence - StringEquals
# cannot express "this tag key must exist" since there's no value to compare
# yet at creation time.
data "aws_iam_policy_document" "require_tags" {
  statement {
    sid    = "DenyUntaggedS3BucketCreation"
    effect = "Deny"
    actions = [
      "s3:CreateBucket",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/CostCenter"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyUntaggedS3BucketCreationTeam"
    effect = "Deny"
    actions = [
      "s3:CreateBucket",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/Team"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyUntaggedS3BucketCreationApplication"
    effect = "Deny"
    actions = [
      "s3:CreateBucket",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/Application"
      values   = ["true"]
    }
  }

  statement {
    sid    = "DenyUntaggedS3BucketCreationEnvironment"
    effect = "Deny"
    actions = [
      "s3:CreateBucket",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/Environment"
      values   = ["true"]
    }
  }
}

resource "aws_organizations_policy" "require_tags" {
  name        = "${local.name}-require-abac-tags"
  description = "Denies creating S3 buckets that are missing any of the ABAC policy tags (CostCenter, Team, Application, Environment)."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.require_tags.json
}

resource "aws_organizations_policy_attachment" "require_tags" {
  count     = var.scp_target_id != "" ? 1 : 0
  policy_id = aws_organizations_policy.require_tags.id
  target_id = var.scp_target_id
}
