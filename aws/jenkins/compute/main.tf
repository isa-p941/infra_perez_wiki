data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = local.state_bucket_name
    region = var.aws_region
    key    = "aws-jenkins-iam/terraform.tfstate"
  }
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_ssm_parameter" "linode_ssh_key" {
  name  = "/infra-perez-wiki/jenkins/linode-ssh-key"
  type  = "SecureString"
  value = var.linode_ssh_private_key
}

resource "aws_ssm_parameter" "exporter_basic_auth_hash" {
  name  = "/infra-perez-wiki/jenkins/exporter-basic-auth-hash"
  type  = "SecureString"
  value = var.exporter_basic_auth_hash
}

resource "aws_ssm_parameter" "jenkins_admin_password" {
  name  = "/infra-perez-wiki/jenkins/admin-password"
  type  = "SecureString"
  value = var.jenkins_admin_password
}

resource "aws_security_group" "jenkins" {
  name        = "infra-perez-wiki-jenkins"
  description = "Jenkins UI (admin only) and node_exporter (auth-protected)"

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "node_exporter, basic-auth protected"
    from_port   = 9100
    to_port     = 9100
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

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = data.terraform_remote_state.iam.outputs.jenkins_instance_profile_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/user_data.sh.tpl", {
    aws_region             = var.aws_region
    ssh_key_param_name     = aws_ssm_parameter.linode_ssh_key.name
    exporter_hash_param    = aws_ssm_parameter.exporter_basic_auth_hash.name
    admin_password_param   = aws_ssm_parameter.jenkins_admin_password.name
    linode_host            = var.linode_host
    docker_compose_content = file("${path.module}/docker-compose.yml")
    jcasc_content          = file("${path.module}/jcasc/jenkins.yaml")
  })

  user_data_replace_on_change = true

  tags = {
    Name    = "infra-perez-wiki-jenkins"
    Project = "infra-perez-wiki"
  }
}
