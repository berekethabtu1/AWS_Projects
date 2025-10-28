###########################################
# Providers & required providers
###########################################
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

###########################################
# Variables
###########################################
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# was Webapp -> use lowercase project_name
variable "Webapp" {
  type    = string
  default = "demo-webapp"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "ssh_key_name" {
  type    = string
  default = ""
}

###########################################
# Networking
###########################################
data "aws_availability_zones" "available" {}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${lower(var.Webapp)}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.Webapp}-igw" }
}

resource "aws_subnet" "public" {
  for_each                = toset(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, index(keys(toset(var.public_subnet_cidrs)), each.key))
  tags = {
    Name = "${var.Webapp}-public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each          = toset(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = element(data.aws_availability_zones.available.names, index(keys(toset(var.private_subnet_cidrs)), each.key))
  tags = {
    Name = "${var.Webapp}-private-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.Webapp}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "random_id" "nat_suffix" {
  byte_length = 4
}

#################################################
# Elastic IP for NAT Gateway
#################################################
resource "aws_eip" "nat" {
  tags = {
    Name = "${var.Webapp}-nat-eip"
  }
}

#################################################
# NAT Gateway
#################################################
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = element(values(aws_subnet.public), 0).id
  tags = {
    Name = "${var.Webapp}-nat"
  }
}

#################################################
# Private Route Table for NAT
#################################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.Webapp}-private-rt"
  }
}

#################################################
# Associate Private Subnets with Private Route Table
#################################################
resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}


###########################################
# Security groups
###########################################
resource "aws_security_group" "alb" {
  name        = "${var.Webapp}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.Webapp}-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "${var.Webapp}-ec2-sg"
  description = "Allow traffic from ALB and SSH"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # replace with your IP range in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.Webapp}-ec2-sg" }
}

resource "aws_security_group" "rds" {
  name   = "${var.Webapp}-rds-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.Webapp}-rds-sg" }
}

###########################################
# IAM
###########################################
resource "aws_iam_role" "ec2_role" {
  name = "${var.Webapp}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.Webapp}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

###########################################
# S3 bucket for assets
###########################################
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.Webapp}-assets-${random_id.bucket_suffix.hex}"
  acl    = "private"
  tags   = { Name = "${var.Webapp}-assets" }
}

###########################################
# EC2 / Auto Scaling / Load Balancer
###########################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "web_lt" {
  name_prefix   = "${var.Webapp}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # optional key
  key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
amazon-linux-extras install -y nginx1
systemctl enable nginx
cat > /usr/share/nginx/html/index.html <<'HTML'
<html>
  <body>
    <h1>Hello from ${var.Webapp}</h1>
    <p>Deployed by Terraform</p>
  </body>
</html>
HTML
systemctl start nginx
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.Webapp}-web"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name                = "${var.Webapp}-asg"
  max_size            = var.max_size
  min_size            = var.desired_capacity
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = values(aws_subnet.public)[*].id

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.Webapp}-web"
    propagate_at_launch = true
  }
}

resource "aws_lb" "alb" {
  name               = "${var.Webapp}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(aws_subnet.public)[*].id
  tags               = { Name = "${var.Webapp}-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "${var.Webapp}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path = "/"
    port = "80"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_autoscaling_attachment" "asg_tg_attach" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  lb_target_group_arn    = aws_lb_target_group.web_tg.arn
}

###########################################
# RDS (Postgres)
###########################################
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "${var.Webapp}-rds-subnets"
  subnet_ids = values(aws_subnet.private)[*].id
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.Webapp}-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  skip_final_snapshot    = true
  publicly_accessible    = false
  tags = {
    Name = "${var.Webapp}-rds"
  }
}


###########################################
# Outputs
###########################################
output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "s3_bucket_assets" {
  value = aws_s3_bucket.assets.bucket
}

output "rds_endpoint" {
  value     = aws_db_instance.postgres.address
  sensitive = true
}
