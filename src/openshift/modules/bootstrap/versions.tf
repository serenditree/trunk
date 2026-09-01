terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.29.0"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = ">= 2.1.2"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }
  }
}
