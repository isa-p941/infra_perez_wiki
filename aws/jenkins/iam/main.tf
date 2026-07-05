data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

# Trust anchor for GitHub Actions OIDC tokens.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# Trust policy: only these two repos' workflows can assume this role.
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.perez_wiki_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.infra_repo}:*",
      ]
    }
  }
}

# Role GitHub Actions assumes to manage aws/jenkins/compute.
resource "aws_iam_role" "github_actions_jenkins" {
  name               = "infra-perez-wiki-github-actions-jenkins"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid       = "TerraformStateObjects"
    effect    = "Allow"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${local.state_bucket_name}/aws-jenkins-*"]
  }

  statement {
    sid       = "TerraformStateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket_name}"]
  }

  statement {
    sid    = "EC2Lifecycle"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecurityGroupManagement"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SSMParameterManagement"
    effect = "Allow"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListTagsForResource",
      "ssm:PutParameter",
    ]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/infra-perez-wiki/*"]
  }

  statement {
    sid       = "SSMDescribeParameters"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  statement {
    sid       = "PassInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.jenkins_instance.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_jenkins" {
  name   = "jenkins-compute-management"
  role   = aws_iam_role.github_actions_jenkins.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

# Role the EC2 instance itself assumes.
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins_instance" {
  name               = "infra-perez-wiki-jenkins-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Enables Session Manager shell access with no open SSH port.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.jenkins_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins_instance_permissions" {
  statement {
    sid       = "ReadOwnSecrets"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/infra-perez-wiki/*"]
  }
}

resource "aws_iam_role_policy" "jenkins_instance" {
  name   = "read-jenkins-secrets"
  role   = aws_iam_role.jenkins_instance.id
  policy = data.aws_iam_policy_document.jenkins_instance_permissions.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "infra-perez-wiki-jenkins-instance"
  role = aws_iam_role.jenkins_instance.name
}
