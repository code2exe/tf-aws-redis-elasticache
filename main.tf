terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.11"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = "${var.namespace}_VPC"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.namespace}_IG"
  }
}


resource "aws_route_table" "route" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }
  tags = {
    Name = "${var.namespace}_RT"
  }
}

resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route.id
}


data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.vpc_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  depends_on              = [aws_internet_gateway.gateway]
  tags = {
    Name = "${var.namespace}_Subnet"
  }
}

# # TODO: 
resource "aws_elasticache_subnet_group" "bar" {
  name       = "tf-test-cache-subnet"
  subnet_ids = [aws_subnet.subnet.id]
}

resource "aws_security_group" "default" {
  name        = "redis-allow"
  description = "Allow Redis Connections"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.namespace}-SG"
  }
}



resource "aws_network_acl" "acl" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 6379
    to_port    = 6379
  }
  ingress {
    protocol   = "-1"
    rule_no    = 150
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 6379
    to_port    = 6379
  }
  egress {
    protocol   = "-1"
    rule_no    = 150
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  tags = {
    Name = "${var.namespace}-NACL"
  }
}


# resource "aws_elasticache_replication_group" "example" {
#   automatic_failover_enabled = true
#   # availability_zones            = ["us-west-2a", "us-west-2b"]
#   replication_group_id          = "tf-rep-group-1"
#   replication_group_description = "test description"
#   node_type                     = "cache.t2.micro"
#   number_cache_clusters         = 2
#   security_group_ids            = [aws_security_group.default.id]
#   # parameter_group_name          = "default.redis3.2"
#   port              = 6379
#   subnet_group_name = aws_elasticache_subnet_group.bar.name
#   lifecycle {
#     ignore_changes = [number_cache_clusters]
#   }
# }

resource "aws_elasticache_replication_group" "example" {
  replication_group_id          = "tf-redis-cluster"
  replication_group_description = "test description"
  node_type                     = "cache.t2.small"
  port                          = 6379
  automatic_failover_enabled    = true
  #   snapshot_retention_limit = 5
  #   snapshot_window          = "00:00-05:00"
  security_group_ids            = [aws_security_group.default.id]
  subnet_group_name             = aws_elasticache_subnet_group.bar.name

  cluster_mode {
    replicas_per_node_group = 1
    num_node_groups         = var.node_groups
  }
}


resource "tls_private_key" "instancessh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "deploy"
  public_key = tls_private_key.instancessh.public_key_openssh
}

data "template_file" "user_data" {
  template = file("./templates/startup.sh")
}

# AWS Instance

resource "aws_instance" "instance" {
  ami                    = var.ec2_ami
  availability_zone      = data.aws_availability_zones.available.names[0]
  instance_type          = "t2.micro"
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id              = aws_subnet.subnet.id
  key_name = aws_key_pair.deployer.id
  user_data              = data.template_file.user_data.rendered
  tags = {
    name = "${var.namespace}-Instance"
  }
}

resource "local_file" "instancekey" {
  filename = "${path.module}/deploy.pem"
  content  = tls_private_key.instancessh.private_key_pem
}