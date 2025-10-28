# Terraform AWS Web Application Infrastructure

This repository contains a **single-file Terraform project (`main.tf`)** that deploys a full AWS web application environment. The project demonstrates **Infrastructure as Code (IaC)** using Terraform and includes networking, compute, database, security, and storage components.

## **Project Overview**

The infrastructure includes:

- **VPC** with public and private subnets
- **Internet Gateway** and **NAT Gateway** with route tables
- **EC2 Instances** deployed via **Auto Scaling Group**
- **Application Load Balancer (ALB)**
- **PostgreSQL RDS Database** in private subnets
- **IAM Roles and Instance Profiles** for EC2
- **S3 Bucket** for assets
- **Security Groups** for ALB, EC2, and RDS
- **Random IDs** for NAT and S3 bucket uniqueness

## **Technologies Used**

- Terraform (>= 1.2.0)
- AWS (VPC, EC2, RDS, S3, IAM, ALB)
- Postgres

