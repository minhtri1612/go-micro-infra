data "http" "my_public_ip" {
  count = var.admin_ingress_cidr == null ? 1 : 0

  url = "https://checkip.amazonaws.com"

  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  detected_ip        = length(data.http.my_public_ip) > 0 ? "${chomp(data.http.my_public_ip[0].response_body)}/32" : null
  admin_ingress_cidr = coalesce(var.admin_ingress_cidr, local.detected_ip)
}
