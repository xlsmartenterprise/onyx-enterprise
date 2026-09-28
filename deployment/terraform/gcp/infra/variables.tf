variable "project_id" {
  description = "Existing GCP project containing this isolated test environment."
  type        = string
  default     = "internal-tech-tools-enterprise"
}

variable "region" {
  description = "Regional GKE, Cloud SQL, Redis, Artifact Registry and GCS location."
  type        = string
  default     = "asia-southeast2"
}

variable "admin_cidrs" {
  description = "Public IPv4 CIDRs permitted to reach the GKE control plane. Explicit input required; never use 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for cidr in var.admin_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Supply at least one valid, restricted IPv4 admin CIDR; 0.0.0.0/0 is forbidden."
  }
}

variable "network_cidr" {
  description = "Primary private subnet range; avoid overlap with existing routed networks."
  type        = string
  default     = "10.208.0.0/20"
}

variable "pods_cidr" {
  description = "GKE Pod secondary range; avoid overlap with peered/VPN networks."
  type        = string
  default     = "10.209.0.0/16"
}

variable "services_cidr" {
  description = "GKE Services secondary range; avoid overlap with peered/VPN networks."
  type        = string
  default     = "10.210.0.0/20"
}

variable "private_services_cidr" {
  description = "Reserved /16 range for Cloud SQL and Memorystore Private Services Access."
  type        = string
  default     = "10.211.0.0"
}

variable "cluster_name" {
  type    = string
  default = "onyx-staging"
}

variable "node_machine_type" {
  description = "Three-zone baseline: at least one node per zone, with headroom for the full Onyx + OpenSearch chart."
  type        = string
  default     = "e2-standard-8"
}

variable "sql_tier" {
  type    = string
  default = "db-custom-4-15360"
}
