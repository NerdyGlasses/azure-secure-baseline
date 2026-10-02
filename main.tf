# VERSION 1: INTENTIONALLY INSECURE (for the before/after demo).
# Do not deploy. Scan with: checkov -d .

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# ---------- Networking ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.prefix}-app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Fix: SSH restricted to a known-trusted range (e.g. a corporate VPN CIDR or bastion subnet),
  # not the entire internet. Replace with your actual trusted range.
  security_rule {
    name                       = "allow-ssh-trusted-only"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.trusted_admin_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# ---------- Storage ----------
#checkov:skip=CKV_AZURE_33:Queue logging IS enabled, via the dedicated azurerm_storage_account_queue_properties
# resource below (required since the inline queue_properties block is deprecated in AzureRM v4 and
# removed in v5). Checkov 3.3.22's rule for this check does not yet recognize the split-resource pattern.
resource "azurerm_storage_account" "data" {
  name                     = "${var.prefix}data001"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  # Fix (CKV_AZURE_206): geo-redundant replication instead of single-region LRS
  account_replication_type = "GRS"

  # Fix (CKV_AZURE_44 / CKV_AZURE_59 / CKV_AZURE_190): modern TLS, HTTPS only, no public access
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  # Fix (CKV2_AZURE_40): force Entra ID / RBAC auth instead of account shared keys
  shared_access_key_enabled = false

  # Fix (CKV2_AZURE_41): any SAS token issued (if ever re-enabled) must expire within 24h
  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  # Fix (CKV2_AZURE_38): soft delete on blobs and containers so deletions are recoverable
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

}

# Fix (CKV_AZURE_33 / CKV2_AZURE_21): storage request logging, feeds Sentinel/Log Analytics later.
# Split into its own resource because `queue_properties` nested in azurerm_storage_account
# is deprecated and being removed in AzureRM provider v5.
resource "azurerm_storage_account_queue_properties" "data" {
  storage_account_id = azurerm_storage_account.data.id

  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
}

resource "azurerm_storage_container" "files" {
  name                  = "files"
  storage_account_id    = azurerm_storage_account.data.id
  # Fix (CKV_AZURE_34): private container, no anonymous read access
  container_access_type = "private"
}

# ---------- Key Vault ----------
resource "azurerm_key_vault" "kv" {
  name                = "${var.prefix}-kv-001"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Fix (CKV_AZURE_110 / CKV_AZURE_42): purge protection so deleted secrets/keys can't be
  # permanently destroyed before the retention window - protects against malicious or accidental deletion
  purge_protection_enabled = true

  # Fix (CKV_AZURE_189): no public network access; only private endpoint / trusted services reach it
  public_network_access_enabled = false

  # Fix (CKV_AZURE_109): explicit deny-by-default firewall; Azure services bypass is still allowed
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}
