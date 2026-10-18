variable "gcp_project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for Artifact Registry and Cloud Run."
  type        = string
}

variable "image_uri" {
  description = "Existing immutable Artifact Registry image URI, including @sha256 digest."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "image_uri must end with an immutable @sha256 digest."
  }
}

variable "jwt_issuer_uri" {
  description = "Expected JWT issuer, passed to JWT_ISSUER_URI."
  type        = string
}

variable "jwt_jwk_set_uri" {
  description = "JWT JWK set URL, passed to JWT_JWK_SET_URI."
  type        = string
}

variable "cors_allowed_origins" {
  description = "Comma-separated browser origins, passed to CORS_ALLOWED_ORIGINS."
  type        = string
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "ride-matching"
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "ride-matching"
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

variable "invoker_members" {
  description = "IAM members allowed to invoke Cloud Run. allUsers is appropriate only when application JWT authentication is retained."
  type        = list(string)
  default     = ["allUsers"]
}
