provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}

data "aws_iam_openid_connect_provider" "default" {
  url = "https://${local.github_oidc_domain}"
}

# resource "aws_iam_openid_connect_provider" "default" {
#   url             = "https://${local.github_oidc_domain}"
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
# }
