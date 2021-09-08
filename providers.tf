terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 2.21.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.40.0"
    }
  }
}

provider "aws" {}