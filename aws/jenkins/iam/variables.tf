variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  type    = string
  default = "isa-p941"
}

variable "perez_wiki_repo" {
  type    = string
  default = "perez_wiki"
}

variable "infra_repo" {
  type    = string
  default = "infra_perez_wiki"
}

variable "state_bucket_prefix" {
  type    = string
  default = "infra-perez-wiki-tfstate"
}
