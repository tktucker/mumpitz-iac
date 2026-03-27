# =============================================================================
# DNS MODULE — ACM Certificate + Route53 ALIAS + HTTPS ALB Listener
# =============================================================================
#
# Creates:
#   - ACM public certificate for app.<environment>.<domain> (DNS validation)
#   - Route53 CNAME records for ACM DNS validation
#   - Route53 type A ALIAS record → ALB (free, handles IP changes, supports health checks)
#   - HTTPS listener on port 443 (CodeDeploy manages traffic shifting)
# =============================================================================

variable "project_name"   { type = string }
variable "environment"    { type = string }
variable "domain_name"    { type = string }  # e.g. "mumpitz.org"
variable "alb_arn"        { type = string }
variable "alb_dns_name"   { type = string }
variable "alb_zone_id"    { type = string }
variable "tg_blue_arn"    { type = string }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  app_fqdn    = "app.${var.environment}.${var.domain_name}"  # e.g. app.dev.mumpitz.org
}

# -----------------------------------------------------------------------------
# Look up the hosted zone for the root domain
# The zone must already exist in Route53 (created outside Terraform or manually)
# -----------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# -----------------------------------------------------------------------------
# ACM Public Certificate
#
# Non-exportable by default — AWS holds the private key in a managed HSM.
# DNS validation allows automatic renewal without human intervention.
# The certificate covers the environment-specific subdomain only.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "app" {
  domain_name               = local.app_fqdn
  validation_method         = "DNS"

  options {
    # Default is ENABLED; explicit here for clarity and exam study.
    # Certificate Transparency logs help detect mis-issued certificates.
    certificate_transparency_logging_preference = "ENABLED"
  }

  tags = {
    Name        = "${local.name_prefix}-acm-cert"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    # Create the new cert before destroying the old one during replacements.
    # This prevents downtime if the cert domain changes.
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Route53 DNS Validation Records
#
# ACM provides one CNAME record per domain to prove you control the domain.
# for_each handles the case where a cert covers multiple SANs.
# -----------------------------------------------------------------------------
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true  # Safe to overwrite if re-applying across environments
}

# -----------------------------------------------------------------------------
# ACM Certificate Validation
#
# Terraform waits here until the certificate reaches ISSUED status.
# DNS validation typically completes within 2-5 minutes once CNAME records
# propagate. This resource has no AWS API effect — it just gates the plan.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# HTTPS Listener — port 443 (production traffic)
#
# CodeDeploy manages `default_action` during blue/green deployments, swapping
# the target group from blue to green. ignore_changes prevents Terraform from
# reverting CodeDeploy's changes on the next `terraform apply`.
#
# ssl_policy: TLS 1.2+ only; TLS 1.3 preferred where supported.
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = var.alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.tg_blue_arn
  }

  lifecycle {
    ignore_changes = [default_action]  # CodeDeploy manages this during blue/green
  }
}

# -----------------------------------------------------------------------------
# Route53 ALIAS Record — app.<environment>.<domain> → ALB
#
# ALIAS records differ from CNAMEs in two key ways:
#   1. They resolve directly to ALB IPs (no extra DNS hop)
#   2. ALB zone_id pairs with the ALB DNS name for proper health-check routing
#
# evaluate_target_health = true means Route53 will stop returning this record
# if all ALB targets are unhealthy — a free layer of DNS-level failover.
# -----------------------------------------------------------------------------
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "alb_https_listener_arn" { value = aws_lb_listener.https.arn }
output "certificate_arn"        { value = aws_acm_certificate.app.arn }
output "app_url"                { value = "https://${local.app_fqdn}" }
