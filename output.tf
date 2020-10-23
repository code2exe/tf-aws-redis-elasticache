output "configuration_endpoint_address" {
  value = aws_elasticache_replication_group.example.configuration_endpoint_address
}
output "redis_instance_ip_addr" {
  value = aws_instance.instance.public_ip
}