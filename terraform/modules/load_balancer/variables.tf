variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "enable_frontend" {
  description = "Whether frontend Cloud Run service is enabled"
  type        = bool
  default     = true
}

variable "frontend_service_name" {
  description = "Cloud Run frontend service name"
  type        = string
  default     = ""
}

variable "backend_service_name" {
  description = "Cloud Run API service name"
  type        = string
}

variable "frontend_domain" {
  description = "Public hostname for frontend or unified domain (A record -> web_lb_ip). Empty = HTTP IP only."
  type        = string
  default     = ""
}

variable "backend_domain" {
  description = "Optional separate public hostname for API (e.g., api.example.com). If empty and frontend_domain is set, API routes on https://<frontend_domain>/api/*."
  type        = string
  default     = ""
}

variable "rate_limit_count" {
  description = "Max requests per IP within rate_limit_interval_sec before throttle"
  type        = number
  default     = 1000
}

variable "rate_limit_interval_sec" {
  description = "Rate limit window in seconds"
  type        = number
  default     = 60
}

variable "allow_rules" {
  description = "Cloud Armor source allow rules. Empty = public (WAF + rate limit, default allow). Non-empty = these allows first, then WAF, then default deny, with no throttle."
  type = list(object({
    description = string
    cidrs       = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.allow_rules : length(rule.cidrs) >= 1 && length(rule.cidrs) <= 10
    ])
    error_message = "Each Cloud Armor allow rule must list 1 to 10 CIDRs."
  }
}

variable "route_api_docs" {
  description = "When true, send Swagger/ReDoc/OpenAPI paths to the API backend."
  type        = bool
  default     = false
}
