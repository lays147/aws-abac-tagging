variable "scp_target_id" {
  type        = string
  description = "AWS Organizations root or OU ID to attach the tag-enforcement SCP to. Leave empty if this account is not an Organizations management account - the SCP resources will still be created but not attached."
  default     = ""
}
