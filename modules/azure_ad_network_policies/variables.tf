# Required Variables
variable "snowflake_network_security_database" {
  type        = string
  description = "The name of the database to store tables, procedures, and network rules for security."
}

variable "snowflake_network_security_schema" {
  type        = string
  description = "The name of the schema to store tables, procedures, and network rules for security."
}

# Optional Variables
