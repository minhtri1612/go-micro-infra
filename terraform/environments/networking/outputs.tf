output "peering_ids" {
  value = {
    mgmt_dev     = try(aws_vpc_peering_connection.mgmt_dev[0].id, null)
    mgmt_prod    = try(aws_vpc_peering_connection.mgmt_prod[0].id, null)
    jenkins_dev  = try(aws_vpc_peering_connection.jenkins_dev[0].id, null)
    jenkins_prod = try(aws_vpc_peering_connection.jenkins_prod[0].id, null)
  }
}
