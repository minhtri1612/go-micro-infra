data "http" "my_public_ip" {
  count = var.admin_ingress_cidr == null ? 1 : 0

  url = "https://checkip.amazonaws.com"

  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  admin_ingress_cidr = coalesce(
    var.admin_ingress_cidr,
    "${chomp(data.http.my_public_ip[0].response_body)}/32"
  )
}
