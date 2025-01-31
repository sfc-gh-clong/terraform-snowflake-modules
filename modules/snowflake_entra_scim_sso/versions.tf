terraform {

  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = ">= 1.0.0"

      configuration_aliases = [
        snowflake.security_integration_role,
        snowflake.securityadmin
      ]
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0.2"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1"
    }
  }
}