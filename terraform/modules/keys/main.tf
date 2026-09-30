# EC2 key pair per environment. The private key lands next to the root module
# (gitignored) and is what Ansible uses to reach the OpenVPN host and, through
# it, the private RKE2 nodes.
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key-${var.environment}"
  public_key = tls_private_key.this.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.this.private_key_pem
  filename        = pathexpand(var.key_filename)
  file_permission = "0600"
}
