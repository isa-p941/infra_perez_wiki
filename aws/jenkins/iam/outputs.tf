output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_jenkins.arn
}

output "jenkins_instance_profile_name" {
  value = aws_iam_instance_profile.jenkins.name
}

output "jenkins_instance_role_arn" {
  value = aws_iam_role.jenkins_instance.arn
}
