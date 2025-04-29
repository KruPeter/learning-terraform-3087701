output "environment_url" {
  description = "Environment url"
  value       = module.web_alb.dns_name
}
