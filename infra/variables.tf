variable "project_id" {
  description = "The shared class project."
  type        = string
  default     = "data-engineering-i2"
}

variable "region" {
  description = "Everything lives in one region: bucket, datasets, queries."
  type        = string
  default     = "europe-west1"
}

variable "group" {
  description = "Group short name, used in resource names."
  type        = string
  default     = "group2"
}
