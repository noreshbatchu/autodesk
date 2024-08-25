provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Public Subnet 1
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"    # CIDR block for public subnet 1
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true       # Ensures instances in this subnet get public IPs
}

# Public Subnet 2
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"    # CIDR block for public subnet 2
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true       # Ensures instances in this subnet get public IPs
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group for Jenkins
resource "aws_security_group" "jenkins_sg" {
  vpc_id = aws_vpc.main.id

  # Allow HTTP access
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH access only from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["60.254.125.96/32"]  # Replace with your IP address
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR Repository
resource "aws_ecr_repository" "hello_world" {
  name = "hello-world"
}

# ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "hello-world-cluster"
}

# Application Load Balancer
resource "aws_lb" "ecs_lb" {
  name               = "ecs-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]  # Two subnets in different AZs
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "ecs_tg" {
  name     = "ecs-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Listener for Load Balancer
resource "aws_lb_listener" "ecs_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# EC2 Instance for Jenkins (without user_data)
resource "aws_instance" "jenkins" {
  ami           = "ami-066784287e358dad1"  # Ubuntu Server 20.04 LTS - replace with the latest AMI ID if needed
  instance_type = "t2.medium"
  key_name      = "linkp"

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]  # Security group for Jenkins
  subnet_id              = aws_subnet.public_subnet_1.id       # Subnet with public IP

  associate_public_ip_address = true  # Ensure the instance gets a public IP

  tags = {
    Name = "Jenkins-Server"
  }
}

# Output the public IP of the Jenkins server
output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}
