variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource this module creates."
  type        = string
  default     = "mirrord-ecs-quickstart"
}

variable "mirrord_api_key" {
  description = "MetalBear Cloud mode: the MetalBear API key for serverless workloads. It begins with metalbear_key_."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.mirrord_api_key == null || startswith(coalesce(var.mirrord_api_key, "-"), "metalbear_key_")
    error_message = "The MetalBear API key begins with metalbear_key_."
  }
}

variable "eks_cluster_name" {
  description = "Operator-hosted mode: the EKS cluster that runs the mirrord Operator with sessions-manager enabled. Leave unset for MetalBear Cloud mode."
  type        = string
  default     = null
}

variable "eks_workload_group" {
  description = "Operator-hosted mode: the Kubernetes group bound to the mirrord-operator-sessions-manager-agent ClusterRole."
  type        = string
  default     = "mirrord-ecs-workloads"
}

variable "mirrord_service" {
  description = "Service name developers target as serverless/<name> in mirrord.json."
  type        = string
  default     = "orders"
}

variable "mirrord_environment" {
  description = "Environment name developers set as target.namespace in mirrord.json."
  type        = string
  default     = "quickstart"
}

variable "mirrord_bootstrap_image" {
  description = "mirrord remote bootstrap image. Pin a release tag, not latest."
  type        = string
  default     = "ghcr.io/metalbear-co/mirrord-remote-bootstrap:3.223.0"
}

variable "app_image" {
  description = "Image of the orders service. Must be glibc-based (not Alpine)."
  type        = string
  default     = "ghcr.io/metalbear-co/mirrord-ecs-quickstart:latest"
}
