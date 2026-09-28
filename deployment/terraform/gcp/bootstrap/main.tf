terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0, < 8.0"
    }
  }

  # Local state is temporary until this bucket exists. After apply, copy
  # state-backend.tf.example into place and migrate with terraform init.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type    = string
  default = "internal-tech-tools-enterprise"
}

variable "region" {
  type    = string
  default = "asia-southeast2"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_storage_bucket" "terraform_state" {
  name                        = "${var.project_id}-${data.google_project.current.number}-onyx-tfstate"
  project                     = var.project_id
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  # Keep previous state versions for recovery; bound long-term storage costs.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 100
      with_state         = "ARCHIVED"
    }
  }
}

output "state_bucket" {
  value = google_storage_bucket.terraform_state.name
}
