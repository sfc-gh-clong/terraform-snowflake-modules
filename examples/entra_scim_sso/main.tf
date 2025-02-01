#############################################
# Create ADMIN_DB and schemas
#############################################

resource "snowflake_database" "admin_db" {
  provider = snowflake
  name     = "ADMIN_DB"
}

resource "snowflake_schema" "network_security" {
  provider = snowflake.accountadmin
  database = snowflake_database.admin_db.name
  name     = "NETWORK_SECURITY"
}

#############################################
# Set up network policies
#############################################

module "azure_ad_network_policies" {
  source = "../../modules/azure_ad_network_policies"

  providers = {
    snowflake.accountadmin = snowflake.accountadmin
  }

  snowflake_network_security_database = snowflake_database.admin_db.name
  snowflake_network_security_schema   = snowflake_schema.network_security.name
}

#############################################
# Set up SCIM and SSO with Entra ID
#############################################

module "snowflake_entra_scim_sso" {
  source = "../../modules/snowflake_entra_scim_sso"

  providers = {
    snowflake.security_integration_role = snowflake.accountadmin
    snowflake.securityadmin             = snowflake.securityadmin
  }

  # Azure
  microsoft_entra_app_name            = "Terraform Snowflake SSO Example"
  microsoft_entra_tenant_id           = "00000000-0000-0000-0000-000000000000"
  microsoft_entra_notification_emails = ["email@example.com"]

  # Snowflake
  snowflake_account_identifier = "<orgname>-<account_name>"
  scim_integration_network_policy = module.azure_ad_network_policies.azure_ad_network_policy_name
}
