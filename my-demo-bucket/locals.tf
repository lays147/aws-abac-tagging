locals {
  name = "aws-abac-tagging"

  tags = {
    # CostCenter  = "payments"
    Team        = "pix"
    Application = "aws-abac-tagging" # must equal the GitHub repo name this bucket should be synced from
    Environment = terraform.workspace
  }
}
