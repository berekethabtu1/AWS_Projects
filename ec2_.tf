provider "aws" {
  region = "us-east-2"
}

# 0️⃣ Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# 1️⃣ Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# 2️⃣ Generate SSH key pair
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "terraform_key" {
  key_name   = "terraform-key1"
  public_key = tls_private_key.example.public_key_openssh
}

# Save private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.example.private_key_pem
  filename = "${path.module}/terraform-key.pem"
}

# 3️⃣ Security Group allowing SSH and HTTP
resource "aws_security_group" "allow_ssh" {
  name        = "allow-ssh-http"
  description = "Allow SSH and HTTP access"
  vpc_id      =  "vpc-02a275339848fa577"
  

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
}

# 4️⃣ EC2 Instance in the public subnet
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.terraform_key.key_name
  subnet_id              = "subnet-0dab858696e6bed9d"  # <- your public subnet
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from user_data file!</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "WebServerInstance"
  }
}

# 5️⃣ Output public IP
output "public_ip" {
  value = aws_instance.web_server.public_ip
}
