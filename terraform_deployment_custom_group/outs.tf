output "custom_groups" {
  value = {
    for group in google_cloud_identity_group.custom_group :
    group.display_name => {
      id : group.id,
      name : group.name,
      display_name : group.display_name,
      description : group.description,
      create_time : group.create_time,
      update_time : group.update_time
    }
  }
}