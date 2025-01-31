resource "random_uuid" "snowflake_sso_scim_oauth_id" {}
resource "random_uuid" "snowflake_sso_scim_user_app_role_id" {}
resource "random_uuid" "snowflake_sso_scim_msiam_access_app_role_id" {}

# Get Enterprise application template for snowflake
data "azuread_application_template" "snowflake_for_microsoft_entra_id" {
  display_name = "Snowflake for Microsoft Entra ID"
}

# Create Entra application registration
resource "azuread_application" "snowflake_sso_scim" {
  display_name     = var.microsoft_entra_app_name
  template_id      = data.azuread_application_template.snowflake_for_microsoft_entra_id.template_id
  
  owners           = local.microsoft_entra_app_owner_ids

  sign_in_audience = "AzureADMyOrg"

  web {
    homepage_url  = "https://${var.snowflake_account_identifier}.snowflakecomputing.com"
    redirect_uris = ["https://${var.snowflake_account_identifier}.snowflakecomputing.com/fed/login"]

    implicit_grant {
      id_token_issuance_enabled = true
    }
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "msiam_access"
    display_name         = "msiam_access"
    enabled              = true
    id                   = random_uuid.snowflake_sso_scim_msiam_access_app_role_id.result
  }

  app_role {
    allowed_member_types = ["User"]
    description          = "User"
    display_name         = "User"
    enabled              = true
    id                   = random_uuid.snowflake_sso_scim_user_app_role_id.result
  }

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access ${var.snowflake_account_identifier} on behalf of the signed-in user."
      admin_consent_display_name = "Access ${var.snowflake_account_identifier}"
      enabled                    = true
      id                         = random_uuid.snowflake_sso_scim_oauth_id.result
      type                       = "User"
      user_consent_description   = "Allow the application to access ${var.snowflake_account_identifier} on your behalf."
      user_consent_display_name  = "Access ${var.snowflake_account_identifier}"
      value                      = "user_impersonation"
    }
  }

  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

# Set application identifier URI
resource "azuread_application_identifier_uri" "snowflake_sso_scim" {
  application_id = azuread_application.snowflake_sso_scim.id
  identifier_uri = "https://${var.snowflake_account_identifier}.snowflakecomputing.com"
}

# Update Service Principal to support SAML SSO
resource "azuread_service_principal" "snowflake_sso_scim" {
  client_id                     = azuread_application.snowflake_sso_scim.client_id
  use_existing                  = true
  preferred_single_sign_on_mode = "saml"
  notification_email_addresses  = var.microsoft_entra_notification_emails
  app_role_assignment_required  = true

  feature_tags {
    enterprise = true
    custom_single_sign_on = true
    gallery = true
  }
}

# Store the SAML signing certificate rotation in Terraform state
resource "time_rotating" "saml_certificate_rotation" {
  rotation_days = var.saml_certificate_expiration_in_days
}

# Store static time in state (minus 30 days to allow for some time before the cert expires)
resource "time_static" "rotate_saml_certificate" {
  rfc3339 = timeadd(time_rotating.saml_certificate_rotation.rfc3339, "-720h")
}

# Create SAML2 certificate with end date and set replacement triggered by rotation time
resource "azuread_service_principal_token_signing_certificate" "saml_certificate" {
  service_principal_id = azuread_service_principal.snowflake_sso_scim.id
  end_date             = time_rotating.saml_certificate_rotation.rotation_rfc3339

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_static.rotate_saml_certificate]
  }
}

# Create provisioner role for SCIM integration
resource "snowflake_account_role" "aad_provisioner" {
  provider = snowflake.securityadmin

  name     = "AAD_PROVISIONER"
  comment  = "Role to provision AAD groups"
}

# Grant privileges to provisioner role
resource "snowflake_grant_privileges_to_account_role" "aad_provisioner_privileges" {
  provider = snowflake.securityadmin

  privileges        = ["CREATE ROLE", "CREATE USER"]
  account_role_name = snowflake_account_role.aad_provisioner.name
  on_account        = true
}

# Grant provisioner role to accountadmin role
resource "snowflake_grant_account_role" "aad_provisioner_to_accountadmin" {
  provider         = snowflake.securityadmin

  role_name        = snowflake_account_role.aad_provisioner.name
  parent_role_name = "ACCOUNTADMIN"
}

# Create SCIM integration for Entra
resource "snowflake_scim_integration" "entra_id_scim" {
  provider       = snowflake.security_integration_role

  name           = var.snowflake_scim_integration_name
  enabled        = true
  run_as_role    = snowflake_account_role.aad_provisioner.name
  scim_client    = "AZURE"
  network_policy = var.scim_integration_network_policy
  comment        = "User and role synchronization via Entra ID application: ${var.microsoft_entra_app_name}"
}

# Returns a new SCIM access token that is valid for six months
data "snowflake_system_generate_scim_access_token" "scim_access_token" {
  provider         = snowflake.security_integration_role
  integration_name = snowflake_scim_integration.entra_id_scim.name
}

# Rotate the SCIM access token every 5 months (automatically expires 6 months, giving 1 month buffer)
resource "time_rotating" "scim_token_rotation" {
  rotation_months = 5
}

# Store the SCIM access token in service principal
resource "azuread_synchronization_secret" "scim_secret" {
  service_principal_id = azuread_service_principal.snowflake_sso_scim.id

  lifecycle {
    ignore_changes = [ credential["SecretToken"] ]
    replace_triggered_by = [ time_rotating.scim_token_rotation ]
  }

  credential {
    key   = "BaseAddress"
    value = "https://${var.snowflake_account_identifier}.snowflakecomputing.com/scim/v2/"
  }

  credential {
    key   = "SecretToken"
    value = data.snowflake_system_generate_scim_access_token.scim_access_token.access_token
  }
}

# Create provisioning synchronization job
resource "azuread_synchronization_job" "scim_provisioning" {
  service_principal_id = azuread_service_principal.snowflake_sso_scim.id
  template_id          = "snowFlake"
  enabled              = true

  depends_on = [ azuread_synchronization_secret.scim_secret ]
}

# Create SAML2 integration for Entra
resource "snowflake_saml2_integration" "entra_id_sso" {
  provider = snowflake.security_integration_role

  name                                = var.snowflake_saml2_integration_name
  enabled                             = true
  saml2_issuer                        = "https://sts.windows.net/${var.microsoft_entra_tenant_id}/"
  saml2_sso_url                       = "https://login.microsoftonline.com/${var.microsoft_entra_tenant_id}/saml2"
  saml2_provider                      = "CUSTOM"
  saml2_snowflake_acs_url             = "https://${var.snowflake_account_identifier}.snowflakecomputing.com/fed/login"
  saml2_snowflake_issuer_url          = "https://${var.snowflake_account_identifier}.snowflakecomputing.com"
  saml2_x509_cert                     = azuread_service_principal_token_signing_certificate.saml_certificate.value
  saml2_sp_initiated_login_page_label = var.snowflake_login_page_label
  saml2_enable_sp_initiated           = true
}
