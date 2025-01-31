# Required Variables
variable "microsoft_entra_app_name" {
  type        = string
  description = "This will be the name of the application registration and enterprise application in Microsoft Entra."
}

variable "snowflake_account_identifier" {
  type        = string
  description = "The preferred account identifier consists of the name of the account prefixed by its organization (e.g. myorg-account123)."
}

variable "microsoft_entra_tenant_id" {
  type        = string
  description = "Your unique identifier for Microsoft Entra."
}



# Optional Variables
variable "snowflake_security_integration_owner_role" {
  type        = string
  default     = "ACCOUNTADMIN"
  description = "Role that will create and own the security integrations."
}

variable "snowflake_login_page_label" {
  type        = string
  default     = "Entra ID SSO"
  description = "The string containing the label to display after the 'Log In With' button on the login page."
}

variable "snowflake_saml2_integration_name" {
  type        = string
  default     = "ENTRA_ID_SSO"
  description = "String that specifies the identifier (i.e. name) for the integration; must be unique in your account."
}

variable "snowflake_scim_integration_name" {
  type        = string
  default     = "ENTRA_ID_SCIM"
  description = "String that specifies the identifier (i.e. name) for the integration; must be unique in your account."
}

variable "saml_certificate_expiration_in_days" {
  type        = number
  default     = 2 * 365 # 2 years
  description = "The number of days for the SAML certificate before expiration."
}

variable "microsoft_entra_notification_emails" {
  type        = list(string)
  description = "List of email addresses for Microsoft Entra to send notifications."
  default     = []
}

variable "scim_integration_network_policy" {
  type        = string
  default     = null
  description = "Specifies an existing network policy that controls SCIM network traffic."
}



# Local Variables
data "azuread_client_config" "current" {}
data "azuread_application_published_app_ids" "well_known" {}
data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  microsoft_entra_app_owner_ids = [data.azuread_client_config.current.object_id]
}
