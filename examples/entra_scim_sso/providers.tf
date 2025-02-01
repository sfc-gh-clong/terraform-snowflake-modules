# Configure Terraform
terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "1.0.0"
    }
  }
}

# Configure the default Snowflake provider
provider "snowflake" {
  organization_name = "<orgname>"
  account_name      = "<account_name>"
  user              = "SVC_TERRAFORM"
  authenticator     = "SNOWFLAKE_JWT"
  warehouse         = "COMPUTE_WH"

  role                     = "SYSADMIN"
  preview_features_enabled = ["snowflake_system_generate_scim_access_token_datasource",
                              "snowflake_network_rule_resource",
                              "snowflake_stage_resource",
                              "snowflake_table_resource",
                              "snowflake_procedure_sql_resource",
                              "snowflake_procedure_python_resource"]
}

# Configure additional Snowflake provider aliases
provider "snowflake" {
  organization_name = "<orgname>"
  user              = "SVC_TERRAFORM"
  authenticator     = "SNOWFLAKE_JWT"
  warehouse         = "COMPUTE_WH"

  role                     = "ACCOUNTADMIN"
  alias                    = "accountadmin"
  preview_features_enabled = ["snowflake_system_generate_scim_access_token_datasource",
                              "snowflake_network_rule_resource",
                              "snowflake_stage_resource",
                              "snowflake_table_resource",
                              "snowflake_procedure_sql_resource",
                              "snowflake_procedure_python_resource"]
}

provider "snowflake" {
  account_name      = "<account_name>"
  user              = "SVC_TERRAFORM"
  authenticator     = "SNOWFLAKE_JWT"
  
  role                     = "SECURITYADMIN"
  alias                    = "securityadmin"
  preview_features_enabled = ["snowflake_system_generate_scim_access_token_datasource",
                              "snowflake_network_rule_resource",
                              "snowflake_stage_resource",
                              "snowflake_table_resource",
                              "snowflake_procedure_sql_resource",
                              "snowflake_procedure_python_resource"]
}
