output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.example.primary_endpoint_address
}
output "bento_instance_ip_addr" {
  value = aws_instance.instance.public_ip
}