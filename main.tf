provider "aws" {
  profile = "terraform"
  region  = "us-east-1"
}

locals {
  instance_tag = "by-terraform"
}

######## S3 BACKEND ##########
terraform {
  backend "s3" {
    bucket         = "ttnbucketone"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ttnlocking"
  }
}

###########  Getting VPC Data ###########
data "aws_vpc" "default" {
  filter {
    name   = "isDefault"
    values = ["true"]
  }
}

##### Subnets #####
data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

// Creating Key
resource "tls_private_key" "tls_key" {
  algorithm = "RSA"
}

// Generating Key-Value Pair
resource "aws_key_pair" "generated_key" {
  key_name   = "web-key"
  public_key = tls_private_key.tls_key.public_key_openssh

  tags = {
    Environment = "${local.instance_tag}-test"
  }

  depends_on = [
    tls_private_key.tls_key
  ]
}

### Private Key PEM File ###
resource "local_file" "key_file" {
  content  = tls_private_key.tls_key.private_key_pem
  filename = "web-key.pem"

  depends_on = [
    tls_private_key.tls_key
  ]
}

#### Security Group for Loadbalancer #####
resource "aws_security_group" "lb_sg" {
  name        = "loadbalancer-sg"
  description = "Security Group for Loadbalancer"
  vpc_id      = data.aws_vpc.default.id

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

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

##### Security Group for Instances #####
resource "aws_security_group" "instance_sg" {
  name        = "instance-sg"
  description = "Security Group for Backed Instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

##### Loadbalancer target group ####
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

#### Creating Application Loadbalancer ####
resource "aws_lb" "application_lb" {
  name            = "web-loadbalancer"
  security_groups = [aws_security_group.lb_sg.id]
  subnets         = data.aws_subnets.subnets.ids

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

#### Listener for Loadbalancer ####
resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.application_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.web_tg.arn
    type             = "forward"
  }

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

### Getting AMI Data ####
data "aws_ami" "nginx" {
  filter {
    name   = "name"
    values = ["nginc conf"]
  }

  owners = ["self"]
}

### Launching an AWS Instance ####
resource "aws_instance" "lb_backend" {
  ami             = data.aws_ami.nginx.id
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.instance_sg.name]

  tags = {
    Environment = "${local.instance_tag}-test"
  }
}

// Attach instance to target group
resource "aws_lb_target_group_attachment" "tg_instance_attach" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.lb_backend.id
  port             = 80
}

