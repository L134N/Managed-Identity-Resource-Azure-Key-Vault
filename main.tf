terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.116.0"
    }
    random = {
      source = "hashicorp/random"
      version = "= 3.6.0"
    }
  }
  required_version = ">= 1.5.0"

 /* backend "azurerm" {
    resource_group_name  = "rg-terraform-state"             
    storage_account_name = "terraformstatestorage"          
    container_name       = "tfstate1" 
    key                  = "prod.terraform.tfstate"
  } */
}

provider "azurerm" {
  features {}
    skip_provider_registration = true

}

data "azurerm_client_config" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-webapp-kv"
  location = "East US"
}

# Azure Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "kv-webapp-${random_id.suffix.hex}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  sku_name                    = "standard"
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled    = true
}

# App Service Plan
resource "azurerm_service_plan" "app_plan" {
  name                = "asp-webapp-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

# Dummy Web App with System Assigned Managed Identity
resource "azurerm_linux_web_app" "webapp" {
  name                = "webapp-kv-${random_id.suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.app_plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {}

  app_settings = {
    "KEYVAULT_NAME" = azurerm_key_vault.kv.name
  }
}

# Key Vault Access Policy for Web App Managed Identity
resource "azurerm_key_vault_access_policy" "webapp_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.webapp.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Access policy for current user to create secrets
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete"
  ]
}

# Sample secret
resource "random_password" "secret" {
  length  = 16
  special = true 
}

resource "azurerm_key_vault_secret" "sample_secret" { 
  name         = "ExampleSecret1" 
  value        = random_password.secret.result 
  key_vault_id = azurerm_key_vault.kv.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Outputs for verification
output "webapp_url" {
  value = "https://${azurerm_linux_web_app.webapp.default_hostname}"
}

output "webapp_managed_identity_principal_id" {
  value = azurerm_linux_web_app.webapp.identity[0].principal_id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}