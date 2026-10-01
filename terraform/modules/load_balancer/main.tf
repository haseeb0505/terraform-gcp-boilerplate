# ---------------------------------------------------------------------------
# Cloud Armor — WAF + rate limit
# ---------------------------------------------------------------------------
locals {
  armor_lockdown    = length(var.allow_rules) > 0
  waf_priority_base = local.armor_lockdown ? 1200 : 1000

  owasp_waf_rules = [
    { name = "sqli-v33-stable", description = "SQL injection" },
    { name = "xss-v33-stable", description = "Cross-site scripting" },
    { name = "lfi-v33-stable", description = "Local file inclusion" },
    { name = "rfi-v33-stable", description = "Remote file inclusion" },
    { name = "rce-v33-stable", description = "Remote code execution" },
    { name = "methodenforcement-v33-stable", description = "Method enforcement" },
    { name = "scannerdetection-v33-stable", description = "Scanner detection" },
    { name = "protocolattack-v33-stable", description = "Protocol attack" },
    { name = "php-v33-stable", description = "PHP injection" },
    { name = "sessionfixation-v33-stable", description = "Session fixation" },
  ]

  waf_expressions = {
    "methodenforcement-v33-stable" = "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 1, 'opt_out_rule_ids': ['owasp-crs-v030301-id911100-methodenforcement']})"
    "protocolattack-v33-stable"    = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'opt_out_rule_ids': ['owasp-crs-v030301-id921150-protocolattack', 'owasp-crs-v030301-id921120-protocolattack']})"
  }
}

resource "google_compute_security_policy" "default" {
  name    = "${var.name_prefix}-armor"
  project = var.project_id
  type    = "CLOUD_ARMOR"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = false
    }
  }

  dynamic "rule" {
    for_each = { for i, r in local.owasp_waf_rules : i => r }
    content {
      action   = "deny(403)"
      priority = local.waf_priority_base + tonumber(rule.key)
      match {
        expr {
          expression = lookup(
            local.waf_expressions,
            rule.value.name,
            "evaluatePreconfiguredWaf('${rule.value.name}', {'sensitivity': 1})",
          )
        }
      }
      description = "Deny ${rule.value.description} (OWASP WAF, sensitivity 1)"
    }
  }

  dynamic "rule" {
    for_each = range(local.armor_lockdown ? 0 : 1)
    content {
      action   = "throttle"
      priority = 2000
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = ["*"]
        }
      }
      rate_limit_options {
        conform_action = "allow"
        exceed_action  = "deny(429)"
        enforce_on_key = "IP"
        rate_limit_threshold {
          count        = var.rate_limit_count
          interval_sec = var.rate_limit_interval_sec
        }
      }
      description = "Throttle abusive clients per IP"
    }
  }

  dynamic "rule" {
    for_each = { for i, allow in var.allow_rules : i => allow }
    content {
      action   = "allow"
      priority = 1122 + tonumber(rule.key)
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value.cidrs
        }
      }
      description = rule.value.description
    }
  }

  rule {
    action   = local.armor_lockdown ? "deny(403)" : "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = local.armor_lockdown ? "Default deny" : "Default allow"
  }
}

# ---------------------------------------------------------------------------
# Global IP & Certificate Setup
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "web" {
  name         = "${var.name_prefix}-web-lb-ip"
  project      = var.project_id
  address_type = "EXTERNAL"
}

locals {
  domains       = distinct([for d in [var.frontend_domain, var.backend_domain] : d if d != ""])
  https_enabled = length(local.domains) > 0
  ssl_cert_name = local.https_enabled ? "${var.name_prefix}-cert-${substr(md5(join("-", local.domains)), 0, 8)}" : ""
}

# ---------------------------------------------------------------------------
# Serverless NEGs → Cloud Run
# ---------------------------------------------------------------------------
resource "google_compute_region_network_endpoint_group" "web" {
  count                 = var.enable_frontend ? 1 : 0
  name                  = "${var.name_prefix}-web-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.frontend_service_name
  }
}

resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "${var.name_prefix}-api-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.backend_service_name
  }
}

# ---------------------------------------------------------------------------
# Backend services (+ Cloud Armor)
# ---------------------------------------------------------------------------
resource "google_compute_backend_service" "web" {
  count                 = var.enable_frontend ? 1 : 0
  name                  = "${var.name_prefix}-web-backend"
  project               = var.project_id
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.default.id

  backend {
    group = google_compute_region_network_endpoint_group.web[0].id
  }
}

resource "google_compute_backend_service" "api" {
  name                  = "${var.name_prefix}-api-backend"
  project               = var.project_id
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.default.id

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }
}

# ---------------------------------------------------------------------------
# URL Map
# ---------------------------------------------------------------------------
locals {
  default_backend_service_id = var.enable_frontend ? google_compute_backend_service.web[0].id : google_compute_backend_service.api.id
}

resource "google_compute_url_map" "web" {
  name            = "${var.name_prefix}-web-url-map"
  project         = var.project_id
  default_service = local.default_backend_service_id

  header_action {
    response_headers_to_add {
      header_name  = "Strict-Transport-Security"
      header_value = "max-age=31536000; includeSubDomains; preload"
      replace      = true
    }
  }

  # Frontend or Unified Domain Host Rule
  dynamic "host_rule" {
    for_each = var.frontend_domain != "" ? [var.frontend_domain] : []
    content {
      hosts        = [host_rule.value]
      path_matcher = "frontend-matcher"
    }
  }

  # Separate Backend Domain Host Rule (if configured)
  dynamic "host_rule" {
    for_each = var.backend_domain != "" ? [var.backend_domain] : []
    content {
      hosts        = [host_rule.value]
      path_matcher = "backend-matcher"
    }
  }

  # Matcher for frontend / unified domain
  dynamic "path_matcher" {
    for_each = var.frontend_domain != "" ? [1] : []
    content {
      name            = "frontend-matcher"
      default_service = local.default_backend_service_id

      # Path rule for /api when unified domain is used
      dynamic "path_rule" {
        for_each = var.backend_domain == "" ? [1] : []
        content {
          paths   = ["/api", "/api/*"]
          service = google_compute_backend_service.api.id
        }
      }

      dynamic "path_rule" {
        for_each = var.route_api_docs ? [1] : []
        content {
          paths   = ["/docs", "/docs/*", "/redoc", "/redoc/*", "/openapi.json"]
          service = google_compute_backend_service.api.id
        }
      }
    }
  }

  # Matcher for dedicated backend domain
  dynamic "path_matcher" {
    for_each = var.backend_domain != "" ? [1] : []
    content {
      name            = "backend-matcher"
      default_service = google_compute_backend_service.api.id
    }
  }
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "https_redirect" {
  count   = local.https_enabled ? 1 : 0
  name    = "${var.name_prefix}-web-http-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "web" {
  name    = "${var.name_prefix}-web-http-proxy"
  project = var.project_id
  url_map = local.https_enabled ? google_compute_url_map.https_redirect[0].id : google_compute_url_map.web.id
}

resource "google_compute_global_forwarding_rule" "web" {
  name                  = "${var.name_prefix}-web-http"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.web.id
  ip_address            = google_compute_global_address.web.id
}

# ---------------------------------------------------------------------------
# HTTPS (443) + Managed Certificate
# ---------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "web" {
  count   = local.https_enabled ? 1 : 0
  name    = local.ssl_cert_name
  project = var.project_id

  managed {
    domains = local.domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_ssl_policy" "web" {
  count           = local.https_enabled ? 1 : 0
  name            = "${var.name_prefix}-ssl-policy"
  project         = var.project_id
  profile         = "CUSTOM"
  min_tls_version = "TLS_1_2"

  custom_features = [
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
  ]
}

resource "google_compute_target_https_proxy" "web" {
  count            = local.https_enabled ? 1 : 0
  name             = "${var.name_prefix}-web-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.web.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web[0].id]
  ssl_policy       = google_compute_ssl_policy.web[0].id
}

resource "google_compute_global_forwarding_rule" "web_https" {
  count                 = local.https_enabled ? 1 : 0
  name                  = "${var.name_prefix}-web-https"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.web[0].id
  ip_address            = google_compute_global_address.web.id
}
