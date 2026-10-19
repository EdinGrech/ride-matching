variable "gcp_project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for Artifact Registry and Cloud Run."
  type        = string
}

variable "build_id" {
  description = "Cloud Build image tag. Use a new value for every deployment."
  type        = string
  default     = "loadtest"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{0,127}$", var.build_id))
    error_message = "build_id must be a valid Docker tag."
  }
}

variable "test_run_id" {
  description = "Identifier applied to the Cloud Run revision and k6 metrics. Use a new value for every test."
  type        = string
  default     = "loadtest"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.test_run_id))
    error_message = "test_run_id may contain only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "benchmark_profile" {
  description = "k6 profile for the Cloud Run Job. quick is the fast smoke test."
  type        = string
  default     = "quick"

  validation {
    condition     = contains(["quick", "full"], var.benchmark_profile)
    error_message = "benchmark_profile must be quick or full."
  }
}

# Existing local tfvars files may still contain these former deployment inputs.
# The disposable test stack now derives them from its deployed mock issuer instead.
variable "image_uri" {
  description = "Deprecated compatibility input; ignored."
  type        = string
  default     = null
  nullable    = true
}

variable "jwt_issuer_uri" {
  description = "Deprecated compatibility input; ignored."
  type        = string
  default     = null
  nullable    = true
}

variable "jwt_jwk_set_uri" {
  description = "Deprecated compatibility input; ignored."
  type        = string
  default     = null
  nullable    = true
}

variable "cors_allowed_origins" {
  description = "Deprecated compatibility input; ignored."
  type        = string
  default     = null
  nullable    = true
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "ride-matching-loadtest"
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "ride-matching-loadtest"
}

variable "service_account_id" {
  description = "Runtime service account ID."
  type        = string
  default     = "ride-matching-runtime"
}

variable "container_concurrency" {
  description = "Maximum concurrent requests for the one Cloud Run instance."
  type        = number
  default     = 80

  validation {
    condition     = var.container_concurrency >= 1 && var.container_concurrency <= 1000
    error_message = "container_concurrency must be between 1 and 1000."
  }
}

variable "min_instance_count" {
  description = "Minimum Cloud Run instance count. Keep this at 1 while ride state is in memory."
  type        = number
  default     = 1

  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must be zero or greater."
  }
}

variable "max_instance_count" {
  description = "Maximum Cloud Run instance count. Keep this at 1 until ride state uses shared storage."
  type        = number
  default     = 1

  validation {
    condition     = var.max_instance_count >= 1
    error_message = "max_instance_count must be at least 1."
  }
}

variable "invoker_members" {
  description = "IAM members allowed to invoke Cloud Run. allUsers is appropriate only when application JWT authentication is retained."
  type        = list(string)
  default     = ["allUsers"]
}
