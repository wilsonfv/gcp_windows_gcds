variable "custom_groups" {
  description = "custom google groups"
  type = map(map(string))
  default = {}
}