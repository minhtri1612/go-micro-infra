output "api_dns_name" {
  value = aws_lb.api.dns_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "web_dns_name" {
  value = aws_lb.web.dns_name
}

output "web_http_target_group_arn" {
  value = aws_lb_target_group.web_http.arn
}

output "web_https_target_group_arn" {
  value = aws_lb_target_group.web_https.arn
}
