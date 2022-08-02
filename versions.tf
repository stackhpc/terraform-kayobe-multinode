#provider "openstack" {
# use environment variables
#}
provider "github" {
  owner = var.owner
}

terraform {
  required_version = ">= 0.14"
  backend "local" {
  }
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
    github = {
      source  = "integrations/github"
      version = "4.28.0"
    }
  }
}
