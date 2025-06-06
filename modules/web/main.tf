data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
}


module "web_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs            = ["ap-south-1a", "ap-south-1b"]
  public_subnets = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24"]

  tags = {
    Terraform   = "true"
    Environment = var.environment.name
  }
}


module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.2.0"

  name     = "${var.environment.name}-web"
  min_size = var.asg_min_size
  max_size = var.asg_max_size

  vpc_zone_identifier = module.web_vpc.public_subnets
  security_groups     = [module.web_sg.security_group_id]

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = module.autoscaling.autoscaling_group_name
  lb_target_group_arn    = module.web_alb.target_groups["ex-instance"].arn
}


module "web_alb" {
  source = "terraform-aws-modules/alb/aws"

  name            = "${var.environment.name}-web-alb"
  vpc_id          = module.web_vpc.vpc_id
  subnets         = module.web_vpc.public_subnets
  security_groups = [module.web_sg.security_group_id]

  enable_deletion_protection = false

  listeners = {
    ex-http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  target_groups = {
    ex-instance = {
      name_prefix       = "web-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "instance"
      create_attachment = false

      health_check = {
        enabled             = true
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        interval            = 30
        matcher             = "200"
      }
    }
  }

  tags = {
    Environment = var.environment.name
    Project     = "Example"
  }
}


module "web_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name    = "${var.environment.name}-web_sg"

  vpc_id              = module.web_vpc.vpc_id
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}
