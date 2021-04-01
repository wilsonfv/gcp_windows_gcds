terraform {
  backend "local" {}
}

locals {
  parent_id = "customers/C01lxufso"
}

resource "google_cloud_identity_group" "custom_group" {
  provider = "google-beta"

  for_each = var.custom_groups

  display_name = each.value.display_name

  parent = local.parent_id

  group_key {
    id = each.value.group_key_id
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }
}