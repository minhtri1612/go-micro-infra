output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "openvpn_sg_id" {
  value = aws_security_group.openvpn.id
}

output "node_common_sg_id" {
  value = aws_security_group.node_common.id
}

output "master_sg_id" {
  value = aws_security_group.master.id
}

output "worker_sg_id" {
  value = aws_security_group.worker.id
}

output "web_nlb_sg_id" {
  value = aws_security_group.web_nlb.id
}
