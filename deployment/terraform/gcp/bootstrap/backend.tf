terraform {
  backend "gcs" {
    bucket = "internal-tech-tools-enterprise-322861197394-onyx-tfstate"
    prefix = "onyx/bootstrap"
  }
}
