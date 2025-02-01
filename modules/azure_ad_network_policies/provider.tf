terraform {

  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = ">= 1.0.0"

      configuration_aliases = [
        snowflake.accountadmin
      ]
    }
  }
}