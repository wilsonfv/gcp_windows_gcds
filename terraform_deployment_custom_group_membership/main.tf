terraform {
  backend "local" {}
}

locals {
  parent_id = "customers/C01lxufso"

  memberships_list = flatten(
    [for group_id, sa_list in var.custom_groups_memberships :
    flatten([for sa in sa_list :
          {
            group  = group_id
            member = sa
      }])
  ])
  memberships = {
    for obj in local.memberships_list:
      "${obj.group}_${obj.member}" => obj
  }
}

data "google_cloud_identity_groups" "all_groups" {
  provider = "google-beta"

  parent = local.parent_id
}

resource "google_cloud_identity_group_membership" "custom_group_membership" {
  provider = "google-beta"

  for_each = local.memberships

  group = lookup({
    for obj in data.google_cloud_identity_groups.all_groups.groups:
      obj.group_key[0].id => obj.name
  }, each.value.group, "")

  preferred_member_key {
    id = each.value.member
  }

  roles {
    name = "MEMBER"
  }

  depends_on = [data.google_cloud_identity_groups.all_groups]
}