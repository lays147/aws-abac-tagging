resource "aws_s3_bucket" "this" {
  bucket = "${local.name}-bucket"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket-level ABAC must be explicitly enabled for aws:ResourceTag
# conditions to be evaluated on bucket-level actions like s3:ListBucket
# (see abac/policies.tf's s3_sync policy). Object-level actions already
# evaluate aws:ResourceTag against the bucket's tags without this.
resource "aws_s3_bucket_abac" "this" {
  bucket = aws_s3_bucket.this.bucket
  abac_status {
    status = "Enabled"
  }
}