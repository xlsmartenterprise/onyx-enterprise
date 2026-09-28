# Attached to the GKE-managed nginx backend through public-ingress.yaml.
# Keep chat payloads out of generic WAF rules until false positives are measured.
resource "google_compute_security_policy" "chat" {
  project     = var.project_id
  name        = "onyx-staging-chat-armor"
  description = "Staging HTTPS login rate limit and common scanner path blocking"
  type        = "CLOUD_ARMOR"

  rule {
    priority    = 1000
    description = "Reject common credential and configuration-file probes"
    action      = "deny(403)"
    match {
      expr {
        expression = "request.path == '/.env' || request.path == '/wp-login.php' || request.path == '/phpmyadmin'"
      }
    }
  }

  rule {
    priority    = 2000
    description = "Throttle password login to 20 POST requests per minute per client IP"
    action      = "throttle"
    match {
      expr {
        expression = "request.path == '/api/auth/login' && request.method == 'POST'"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 20
        interval_sec = 60
      }
    }
  }

  rule {
    priority    = 2147483647
    description = "Allow application traffic not matched by a protective rule"
    action      = "allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
