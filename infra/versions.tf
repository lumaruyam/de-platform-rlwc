terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.4"
    }
  }

  # Remote state: one shared state for the group and for CI, in our bucket,
  # outside bronze/ so the lifecycle rules never move it to a colder class.
  backend "gcs" {
    bucket = "data-engineering-i2-group2"
    prefix = "terraform/state"
  }
}
