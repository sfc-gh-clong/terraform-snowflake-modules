#############################################
# Network Rules
#############################################

resource "snowflake_network_rule" "microsoft_egress_network_rule" {
  provider   = snowflake.accountadmin
  database   = var.snowflake_network_security_database
  schema     = var.snowflake_network_security_schema
  name       = "MICROSOFT_EGRESS_NETWORK_RULE"
  comment    = "Network rule to be able to download Microsoft IP ranges from download.microsoft.com."
  mode       = "EGRESS"
  type       = "HOST_PORT"
  value_list = ["www.microsoft.com", "download.microsoft.com"]
}

resource "snowflake_network_rule" "azure_ad_ip_ranges" {
  provider   = snowflake.accountadmin
  database   = var.snowflake_network_security_database
  schema     = var.snowflake_network_security_schema
  name       = "AZURE_AD_IP_RANGES"
  comment    = "Network rule to be able to store Azure Active Directory IP ranges."
  mode       = "INGRESS"
  type       = "IPV4"
  value_list = []

  lifecycle {
    ignore_changes = [value_list]
  }
}

#############################################
# Network Policies
#############################################

resource "snowflake_network_policy" "azure_ad" {
  provider                  = snowflake.accountadmin
  name                      = "AZURE_AD_NETWORK_POLICY"
  comment                   = "Network policy for Azure Active Directory for SCIM integration"
  allowed_network_rule_list = [snowflake_network_rule.azure_ad_ip_ranges.fully_qualified_name]
}

#############################################
# External Access Integrations
#############################################

resource "snowflake_execute" "external_access_integration_microsoft" {
  provider = snowflake.accountadmin
  execute  = <<EOT
    CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION microsoft_access_integration
      ALLOWED_NETWORK_RULES = (${snowflake_network_rule.microsoft_egress_network_rule.fully_qualified_name})
      ENABLED = true
  EOT
  revert   = "DROP EXTERNAL ACCESS INTEGRATION IF EXISTS microsoft_access_integration"
}

#############################################
# Stages
#############################################

resource "snowflake_stage" "azure_ip_stage" {
  provider = snowflake.accountadmin
  database = var.snowflake_network_security_database
  schema   = var.snowflake_network_security_schema
  name     = "AZURE_IP_STAGE"
}

#############################################
# Tables
#############################################

resource "snowflake_table" "azure_ip_ranges" {
  provider = snowflake.accountadmin
  database = var.snowflake_network_security_database
  schema   = var.snowflake_network_security_schema
  name     = "AZURE_IP_RANGES"

  column {
    name = "VAL"
    type = "VARIANT"
  }
}

resource "snowflake_table" "hist_azure_ip_ranges" {
  provider = snowflake.accountadmin
  database = var.snowflake_network_security_database
  schema   = var.snowflake_network_security_schema
  name     = "HIST_AZURE_IP_RANGES"

  column {
    name = "CLOUD"
    type = "VARCHAR"
  }
  column {
    name = "CHANGE_NUMBER"
    type = "NUMBER"
  }
  column {
    name = "SERVICE_NAME"
    type = "VARCHAR"
  }
  column {
    name = "SERVICE_ID"
    type = "VARCHAR"
  }
  column {
    name = "SERVICE_CHANGE_NUMBER"
    type = "NUMBER"
  }
  column {
    name = "REGION"
    type = "VARCHAR"
  }
  column {
    name = "REGION_ID"
    type = "NUMBER"
  }
  column {
    name = "PLATFORM"
    type = "VARCHAR"
  }
  column {
    name = "SYSTEM_SERVICE"
    type = "VARCHAR"
  }
  column {
    name = "ADDRESS_PREFIXES"
    type = "VARIANT"
  }
}

#############################################
# Procedures
#############################################

resource "snowflake_procedure_python" "get_azure_ips" {
  provider   = snowflake.accountadmin
  depends_on = [snowflake_execute.external_access_integration_microsoft]

  database                     = var.snowflake_network_security_database
  schema                       = var.snowflake_network_security_schema
  name                         = "GET_AZURE_IPS"
  return_type                  = "VARCHAR"
  handler                      = "main"
  runtime_version              = "3.11"
  snowpark_package             = "1.26.0"
  external_access_integrations = ["MICROSOFT_ACCESS_INTEGRATION"]
  packages                     = ["requests", "urllib3"]
  execute_as                   = "CALLER"

  procedure_definition = <<EOT
import snowflake.snowpark as snowpark
import requests
import json
import urllib3
session = requests.Session()
def main(session: snowpark.Session):

    furl = ''

    ##############################
    # Get Azure IP Ranges for Public Cloud
    ##############################
    
    azure_public_url = 'https://www.microsoft.com/en-us/download/details.aspx?id=56519'
    http = urllib3.PoolManager()
    response = http.request('GET', azure_public_url)
    data = response.data.decode('utf-8')

    # Find ServiceTags file URL
    start = 'https://download.microsoft.com/'
    end = '.json'
    parts = data.split(start)[1:]
    for part in parts:
        if end in part:
            furl = start + part.split(end)[0] + end

    # Read file contents and store it as JSON in an internal stage
    response = http.request('GET', furl)
    data = response.data.decode('utf-8')    
    values = json.loads(data)
    servicetags_file = "/tmp/ServiceTags_Public.json"
    with open(servicetags_file,'w') as json_file:
        json.dump(values, json_file, indent=4)
    session.file.put(servicetags_file, '@${snowflake_stage.azure_ip_stage.fully_qualified_name}', auto_compress = False, overwrite = True)




    ##############################
    # Get Azure IP Ranges for Gov Cloud
    ##############################
    
    azure_gov_url = 'https://www.microsoft.com/en-us/download/details.aspx?id=57063'
    http = urllib3.PoolManager()
    response = http.request('GET', azure_gov_url)
    data = response.data.decode('utf-8')

    # Find ServiceTags file URL
    start = 'https://download.microsoft.com/'
    end = '.json'
    parts = data.split(start)[1:]
    for part in parts:
        if end in part:
            furl = start + part.split(end)[0] + end

    # Read file contents and store it as JSON in an internal stage
    response = http.request('GET', furl)
    data = response.data.decode('utf-8')    
    values = json.loads(data)
    servicetags_file = "/tmp/ServiceTags_AzureGovernment.json"
    with open(servicetags_file,'w') as json_file:
        json.dump(values, json_file, indent=4)
    session.file.put(servicetags_file, '@${snowflake_stage.azure_ip_stage.fully_qualified_name}', auto_compress = False, overwrite = True)


    
    # Copy files into internal stage
    session.sql('TRUNCATE TABLE ${snowflake_table.azure_ip_ranges.fully_qualified_name}').collect();
    session.sql("""COPY INTO ${snowflake_table.azure_ip_ranges.fully_qualified_name} 
                   FROM @${snowflake_stage.azure_ip_stage.fully_qualified_name} file_format = (type='JSON')
                """).collect();
    session.sql("""
        MERGE INTO ${snowflake_table.hist_azure_ip_ranges.fully_qualified_name} tgt
        USING (
            SELECT 
                val:cloud::varchar AS cloud,
                val:changeNumber::number AS change_number,
                f.value:name::varchar AS service_name,
                f.value:id::varchar AS service_id,
                f.value:properties.changeNumber::number AS service_change_number,
                f.value:properties.region::varchar AS region,
                f.value:properties.regionId::number AS region_id,
                f.value:properties.platform::varchar AS platform,
                f.value:properties.systemService::varchar AS system_service,
                f.value:properties.addressPrefixes AS address_prefixes
            FROM ${snowflake_table.azure_ip_ranges.fully_qualified_name},
                LATERAL FLATTEN (INPUT => val:values) f
            ) src
        ON src.change_number = tgt.change_number AND src.cloud = tgt.cloud
        WHEN NOT MATCHED THEN INSERT (cloud, change_number, service_name, service_id, service_change_number, region, region_id, platform, system_service, address_prefixes)
            VALUES (src.cloud, src.change_number, src.service_name, src.service_id, src.service_change_number, src.region, src.region_id, src.platform, src.system_service, src.address_prefixes)
    """).collect();

    return "Success"
  EOT
}

resource "snowflake_procedure_sql" "update_azure_network_rule" {
  provider = snowflake.accountadmin
  database = var.snowflake_network_security_database
  schema   = var.snowflake_network_security_schema
  name     = "UPDATE_AZURE_NETWORK_RULE"

  arguments {
    arg_name      = "CLOUD"
    arg_data_type = "VARCHAR"
  }

  arguments {
    arg_name      = "SERVICE_NAME"
    arg_data_type = "VARCHAR"
  }

  arguments {
    arg_name      = "NETWORK_RULE_NAME"
    arg_data_type = "VARCHAR"
  }

  return_type          = "VARCHAR"
  execute_as           = "CALLER"
  procedure_definition = <<EOT
BEGIN
    let ip_list varchar := (
        WITH latest_service_ips AS (
            SELECT 
                MAX(change_number), 
                service_name, 
                MAX(address_prefixes) as address_prefixes
            FROM ${snowflake_table.hist_azure_ip_ranges.fully_qualified_name}
            WHERE cloud = :cloud
              AND service_name = :service_name
            GROUP BY ALL
        ) 
        SELECT 
            '(''' || ARRAY_TO_STRING(ARRAY_AGG(value::VARCHAR), ''', ''') || ''')' as IP_LIST
        FROM latest_service_ips,
        LATERAL FLATTEN(address_prefixes) 
            WHERE NOT CONTAINS(value::VARCHAR, ':')
    );

    EXECUTE IMMEDIATE 'ALTER NETWORK RULE ' || :network_rule_name || ' SET VALUE_LIST = ' || :ip_list || ';';

    return 'Successfully updated ' || :network_rule_name;
END;
  EOT
}

#############################################
# Tasks
#############################################

resource "snowflake_task" "update_azure_ips" {
  provider                                 = snowflake.accountadmin
  database                                 = var.snowflake_network_security_database
  schema                                   = var.snowflake_network_security_schema
  name                                     = "UPDATE_AZURE_IPS"
  user_task_managed_initial_warehouse_size = "XSMALL"
  started                                  = true
  schedule {
    using_cron = "0 5 * * WED America/Los_Angeles"
  }
  sql_statement = <<EOT
BEGIN
    CALL get_azure_ips();
    CALL ${snowflake_procedure_sql.update_azure_network_rule.database}.${snowflake_procedure_sql.update_azure_network_rule.schema}.${snowflake_procedure_sql.update_azure_network_rule.name}('Public', 'AzureActiveDirectory', '${snowflake_network_rule.azure_ad_ip_ranges.fully_qualified_name}');
END
  EOT
}

resource "snowflake_execute" "execute_update_azure_ips_task" {
  provider = snowflake.accountadmin
  execute  = "EXECUTE TASK ${snowflake_task.update_azure_ips.fully_qualified_name}"
  revert   = "SELECT 1"

  depends_on = [snowflake_task.update_azure_ips,
    snowflake_procedure_sql.update_azure_network_rule,
    snowflake_procedure_python.get_azure_ips,
    snowflake_network_policy.azure_ad,
    snowflake_network_rule.azure_ad_ip_ranges,
    snowflake_network_rule.microsoft_egress_network_rule,
    snowflake_stage.azure_ip_stage,
    snowflake_table.azure_ip_ranges,
    snowflake_table.hist_azure_ip_ranges,
    snowflake_execute.external_access_integration_microsoft
  ]
}
